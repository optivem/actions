#!/usr/bin/env bash
# Local smoke-test harness for shared/sonar-retry.sh.
#
# Invokes sonar_retry against a fake binary that returns a scripted sequence
# of exit codes and stderr messages mimicking sonarscanner output. Validates
# the sonar-specific regex (Error 5xx on https://..., Endpoint request timed
# out) and hard-fail pass-through for auth/config errors.
#
#   bash shared/_test-sonar-retry.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fake_dir=$(mktemp -d -t sonar-retry-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/fake-sonar-scanner"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$SONAR_FAKE_SEQ"
idx=$counter
if (( idx >= ${#seq[@]} )); then
    idx=$(( ${#seq[@]} - 1 ))
fi
entry="${seq[$idx]}"
code="${entry%%|*}"
stderr="${entry#*|}"
if [[ -n "$stderr" && "$stderr" != "$entry" ]]; then
    printf '%s\n' "$stderr" >&2
fi
printf 'fake-stdout-%d\n' "$counter"
echo $(( counter + 1 )) >"$FAKE_STATE"
exit "$code"
FAKE
chmod +x "$fake_bin"
export FAKE_STATE="$fake_state"

trap 'rm -rf "$fake_dir"' EXIT

# shellcheck source=./sonar-retry.sh
source "$HERE/sonar-retry.sh"
_SONAR_RETRY_DELAYS=(0 0 0)

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

echo "Test 1: success on first attempt → no retry"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='0|'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout" "fake-stdout-0" "$out"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 2: SonarCloud Error 504 → success on retry"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|ERROR: Error 504 on https://sonarcloud.io/api/ce/submit: <html>...;0|'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-1" "$out"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 3: Endpoint request timed out → success on retry"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|ERROR: Endpoint request timed out;0|'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 4: 4 straight 504s → exhausts retries"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|Error 504 on https://sonarcloud.io/api/x;1|Error 504 on https://sonarcloud.io/api/x;1|Error 504 on https://sonarcloud.io/api/x;1|Error 504 on https://sonarcloud.io/api/x'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

echo "Test 5: HTTP 401 unauthorized hard-fail → 1 attempt, passes through"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|ERROR: HTTP 401 Unauthorized'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 6: Project not found hard-fail → 1 attempt, passes through"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|ERROR: Project key org.example:my-project does not exist'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 7: SONAR_RETRY_DISABLE=1 bypasses retry"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='1|Error 504 on https://sonarcloud.io/api/x;0|'
SONAR_RETRY_DISABLE=1 sonar_retry "$fake_bin" >/dev/null 2>&1 && : || :
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 8: non-classified failure → 1 attempt, passes through with original exit"
echo 0 >"$fake_state"
export SONAR_FAKE_SEQ='42|ERROR: Some unrelated config error'
out=$(sonar_retry "$fake_bin" 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "42" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
