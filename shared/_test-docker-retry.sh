#!/usr/bin/env bash
# Local smoke-test harness for shared/docker-retry.sh.
#
# Runs by shadowing `docker` with a fake on PATH that returns a scripted
# sequence of exit codes and stderr messages. Not wired into CI — run
# manually:
#
#   bash shared/_test-docker-retry.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install a fake `docker` that reads its scripted sequence from env var
# DOCKER_FAKE_SEQ. Format: semicolon-separated list of "exit_code|stderr_text".
# Each call advances a counter in $fake_state.
fake_dir=$(mktemp -d -t docker-retry-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/docker"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$DOCKER_FAKE_SEQ"
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

# Prepend fake dir to PATH so our fake `docker` shadows the real one.
export PATH="$fake_dir:$PATH"

# Override the retry timing for a fast test run.
# shellcheck source=./docker-retry.sh
source "$HERE/docker-retry.sh"
_DOCKER_RETRY_DELAYS=(0 0 0)

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
export DOCKER_FAKE_SEQ='0|'
out=$(docker_retry pull foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout" "fake-stdout-0" "$out"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 2: transient context-deadline → success on attempt 2"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|Error response from daemon: Get "https://ghcr.io/v2/": context deadline exceeded;0|'
out=$(docker_retry pull foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-1" "$out"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 3: transient 502 → 502 → 200 succeeds after 3 attempts"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|received unexpected HTTP status: 502 Bad Gateway;1|received unexpected HTTP status: 503 Service Unavailable;0|'
out=$(docker_retry buildx imagetools create --tag a b 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-2" "$out"
assert_eq "attempt count" "3" "$(<"$fake_state")"

echo "Test 4: 4 straight transients → exhausts retries, returns non-zero"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|i/o timeout;1|i/o timeout;1|i/o timeout;1|i/o timeout'
out=$(docker_retry pull foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

echo "Test 5: hard-fail unauthorized → 1 attempt, passes through"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|unauthorized: authentication required'
out=$(docker_retry pull foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 6: hard-fail manifest unknown → 1 attempt, passes through"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|manifest unknown: manifest unknown'
out=$(docker_retry buildx imagetools inspect foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 7: non-classified failure → 1 attempt, passes through with original exit"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='42|some unclassified error'
out=$(docker_retry pull foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "42" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 8: DOCKER_RETRY_DISABLE=1 bypasses retry"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|context deadline exceeded;0|'
DOCKER_RETRY_DISABLE=1 docker_retry pull foo >/dev/null 2>&1 && : || :
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 9: stdout preserved through retries (captures from final attempt only)"
echo 0 >"$fake_state"
export DOCKER_FAKE_SEQ='1|connection reset by peer;1|TLS handshake timeout;0|'
out=$(docker_retry inspect foo 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout from final attempt" "fake-stdout-2" "$out"

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
