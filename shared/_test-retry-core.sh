#!/usr/bin/env bash
# Local smoke-test harness for shared/retry-core.sh.
#
# Invokes retry_with_policy directly against a fake binary that returns a
# scripted sequence of exit codes and stderr messages. Validates engine
# behaviour without going through a tool-specific wrapper.
#
#   bash shared/_test-retry-core.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fake_dir=$(mktemp -d -t retry-core-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/faketool"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$CORE_FAKE_SEQ"
idx=$counter
if (( idx >= ${#seq[@]} )); then
    idx=$(( ${#seq[@]} - 1 ))
fi
entry="${seq[$idx]}"
code="${entry%%|*}"
stderr="${entry#*|}"
if [[ -n "$stderr" && "$stderr" != "$entry" ]]; then
    # %b (not %s) so fixtures can embed `\n` and emit multi-line output —
    # needed for stack-trace cases, since `read -ra` below stops at the first
    # real newline and so cannot carry one in the sequence string.
    printf '%b\n' "$stderr" >&2
fi
printf 'fake-stdout-%d\n' "$counter"
echo $(( counter + 1 )) >"$FAKE_STATE"
exit "$code"
FAKE
chmod +x "$fake_bin"
export FAKE_STATE="$fake_state"

trap 'rm -rf "$fake_dir"' EXIT

# shellcheck source=./retry-core.sh
source "$HERE/retry-core.sh"
_RETRY_CORE_DELAYS=(0 0 0)

TRANSIENT='HTTP 5[0-9][0-9]|timeout|i/o timeout|connection reset'
HARDFAIL='HTTP 4[0-9][0-9]|denied'

pass=0
fail=0
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS $label"
        (( pass++ )) || true
    else
        echo "  FAIL $label"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        (( fail++ )) || true
    fi
}

echo "Test 1: success on first attempt"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='0|'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout" "fake-stdout-0" "$out"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 2: transient 502 → success on attempt 2"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 502 Bad Gateway;0|'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-1" "$out"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 3: hard-fail HTTP 404 → 1 attempt, passes through"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 404 Not Found'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 4: non-classified failure → 1 attempt, passes through with original exit code"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='42|some unrelated error'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "42" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 5: 4 straight transients → exhausts retries"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|i/o timeout;1|i/o timeout;1|i/o timeout;1|i/o timeout'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

echo "Test 6: empty hard-fail regex still classifies transients correctly"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 502;0|'
out=$(retry_with_policy "$TRANSIENT" "" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 6b: force-retry override wins over hard-fail → retries past a 4xx"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 403 Forbidden while provisioning;0|'
export _RETRY_CORE_FORCE_RETRY='provisioning'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
unset _RETRY_CORE_FORCE_RETRY
assert_eq "exit code" "0" "$code"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 6c: force-retry override unset → 4xx still hard-fails (1 attempt)"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 403 Forbidden while provisioning;0|'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 6d: force-retry override exhausts when failure persists"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 403 Forbidden while provisioning'
export _RETRY_CORE_FORCE_RETRY='provisioning'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
unset _RETRY_CORE_FORCE_RETRY
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

# Stack-frame stripping. A frame is a code identifier, not a failure message,
# so a method name containing a policy keyword must not decide the verdict.
# Regression for gh-optivem run 35261501113, where the frame
# `...DefaultScannerWsClient.failIfUnauthorized(...)` matched the hard-fail
# token `[Uu]nauthorized` and beat a genuine transient 500 — zero retries.
# Here `failIfDenied` plays the same role against this harness's `denied`
# hard-fail token.
echo "Test 6e: transient message + hard-fail keyword in a frame → retries"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 502 Bad Gateway\n\tat com.example.http.Client.failIfDenied(Client.java:88)\n\t... 87 common frames omitted;0|'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "attempt count" "2" "$(<"$fake_state")"

# The same keyword in the MESSAGE must still hard-fail — stripping frames
# must not weaken genuine hard-fail detection.
echo "Test 6f: hard-fail keyword in the message → still 1 attempt despite frames"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 403 denied by policy\n\tat com.example.http.Client.call(Client.java:58)'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

# All-frames output filters down to an empty classification input. `grep -Ev`
# exits 1 there; if that status escaped, the callers' inherited `set -e` would
# abort the loop. Empty must classify as "matches neither" → pass through.
echo "Test 6g: output that is entirely frames → pass through, no set -e abort"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='7|\tat com.example.http.Client.failIfDenied(Client.java:88)\n\t... 3 common frames omitted'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "7" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

# Frames are removed from classification only — the operator must still get
# the complete trace on the pass-through branch.
echo "Test 6h: full unfiltered trace still reaches the caller"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|HTTP 403 denied by policy\n\tat com.example.http.Client.call(Client.java:58)'
combined=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" 2>&1) && code=0 || code=$?
if grep -q "at com.example.http.Client.call" <<<"$combined"; then
    echo "  PASS frame preserved in output"
    (( pass++ )) || true
else
    echo "  FAIL frame preserved in output"
    echo "    expected substring: at com.example.http.Client.call"
    echo "    actual output:      $combined"
    (( fail++ )) || true
fi

echo "Test 7: command with args is forwarded correctly"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='0|'
out=$(retry_with_policy "$TRANSIENT" "$HARDFAIL" test-prefix -- "$fake_bin" arg1 arg2 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout" "fake-stdout-0" "$out"

# Standalone-call regression: real callers like start.sh invoke retry_run as a
# top-level statement under `set -euo pipefail`. If errexit fires inside the
# loop on a failed "$@", retries never happen and stderr is never flushed —
# the symptom is a silent non-zero exit. Driving the call in a child bash
# preserves the bug surface (the test-script's own conditional wrapping would
# mask it).
echo "Test 8: standalone call under set -e completes all retries and surfaces stderr"
echo 0 >"$fake_state"
export CORE_FAKE_SEQ='1|i/o timeout;1|i/o timeout;1|i/o timeout;1|i/o timeout'
combined=$(bash -c '
    set -euo pipefail
    source "'"$HERE"'/retry-core.sh"
    _RETRY_CORE_DELAYS=(0 0 0)
    retry_with_policy "'"$TRANSIENT"'" "'"$HARDFAIL"'" test-prefix -- "'"$fake_bin"'"
' 2>&1) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"
if grep -q "i/o timeout" <<<"$combined"; then
    echo "  PASS stderr surfaced"
    (( pass++ )) || true
else
    echo "  FAIL stderr surfaced"
    echo "    expected substring: i/o timeout"
    echo "    actual output:      $combined"
    (( fail++ )) || true
fi

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
