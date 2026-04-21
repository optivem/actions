#!/usr/bin/env bash
# Local smoke-test harness for shared/gh-retry.sh.
#
# Runs by shadowing `gh` with a fake on PATH that returns a scripted sequence
# of exit codes and stderr messages. Not wired into CI — run manually:
#
#   bash shared/_test-gh-retry.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install a fake `gh` that reads its scripted sequence from env var GH_FAKE_SEQ.
# GH_FAKE_SEQ format: semicolon-separated list of "exit_code|stderr_text".
# Each call advances a counter in $fake_state.
fake_dir=$(mktemp -d -t gh-retry-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/gh"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$GH_FAKE_SEQ"
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

# Prepend fake dir to PATH
export PATH="$fake_dir:$PATH"

# Override the retry timing for a fast test run.
# shellcheck source=./gh-retry.sh
source "$HERE/gh-retry.sh"
_GH_RETRY_DELAYS=(0 0 0)

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

echo "Test 1: transient 502 → 502 → 200 succeeds after 3 attempts"
echo 0 >"$fake_state"
export GH_FAKE_SEQ='1|HTTP 502: Bad Gateway;1|HTTP 502: Bad Gateway;0|'
out=$(gh_retry api foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-2" "$out"
assert_eq "attempt count" "3" "$(<"$fake_state")"

echo "Test 2: HTTP 404 non-retryable → 1 attempt, passes through"
echo 0 >"$fake_state"
export GH_FAKE_SEQ='1|HTTP 404: Not Found'
out=$(gh_retry api foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 3: HTTP 403 rate-limit hard-fail → 1 attempt, passes through"
echo 0 >"$fake_state"
export GH_FAKE_SEQ='1|HTTP 403: API rate limit exceeded'
out=$(gh_retry api foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 4: 4 straight 502s → exhausts retries, returns non-zero"
echo 0 >"$fake_state"
export GH_FAKE_SEQ='1|HTTP 502;1|HTTP 502;1|HTTP 502;1|HTTP 502'
out=$(gh_retry api foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

echo "Test 5: GH_RETRY_DISABLE=1 bypasses retry"
echo 0 >"$fake_state"
export GH_FAKE_SEQ='1|HTTP 502;0|'
GH_RETRY_DISABLE=1 gh_retry api foo >/dev/null 2>&1 && : || :
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
