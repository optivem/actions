#!/usr/bin/env bash
# Local smoke-test harness for shared/git-retry.sh.
#
# Runs by shadowing `git` with a fake on PATH that returns a scripted
# sequence of exit codes and stderr messages. Not wired into CI — run
# manually:
#
#   bash shared/_test-git-retry.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install a fake `git` that reads its scripted sequence from env var
# GIT_FAKE_SEQ. Format: semicolon-separated list of "exit_code|stderr_text".
# Each call advances a counter in $fake_state.
fake_dir=$(mktemp -d -t git-retry-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/git"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$GIT_FAKE_SEQ"
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

# Prepend fake dir to PATH so our fake `git` shadows the real one.
export PATH="$fake_dir:$PATH"

# Override the retry timing for a fast test run.
# shellcheck source=./git-retry.sh
source "$HERE/git-retry.sh"
_GIT_RETRY_DELAYS=(0 0 0)

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

echo "Test 1: push success on first attempt → no retry"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='0|'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout" "fake-stdout-0" "$out"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 2: push transient RPC HTTP 502 → success on attempt 2"
echo 0 >"$fake_state"
# NB: stderr text must not contain ';' — GIT_FAKE_SEQ uses it as a record separator.
export GIT_FAKE_SEQ='1|fatal: unable to access — RPC failed HTTP 502 curl 22 The requested URL returned error: 502;0|'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-1" "$out"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo "Test 3: fetch transient DNS → DNS → success after 3 attempts"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='1|fatal: unable to access: Could not resolve host: github.com;1|fatal: temporary failure in name resolution;0|'
out=$(git_fetch_retry origin main --quiet 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "stdout final attempt" "fake-stdout-2" "$out"
assert_eq "attempt count" "3" "$(<"$fake_state")"

echo "Test 4: push 4 straight transients → exhausts retries, returns non-zero"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='1|Connection reset by peer;1|Connection reset by peer;1|Connection reset by peer;1|Connection reset by peer'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "4" "$(<"$fake_state")"

echo "Test 5: push hard-fail permission denied → 1 attempt, passes through"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='128|fatal: Permission denied (publickey)'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "128" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 6: push hard-fail remote rejected → 1 attempt, passes through"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='1| ! [remote rejected] v1.0.0 -> v1.0.0 (pre-receive hook declined)'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "1" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 7: push hard-fail repository-not-found → 1 attempt, passes through"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='128|fatal: repository '"'"'https://github.com/foo/bar.git/'"'"' not found'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "128" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 8: non-classified failure → 1 attempt, passes through with original exit"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='42|some unclassified git error'
out=$(git_push_retry origin v1.0.0 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "42" "$code"
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 9: GIT_RETRY_DISABLE=1 bypasses retry"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='1|Connection reset by peer;0|'
GIT_RETRY_DISABLE=1 git_push_retry origin v1.0.0 >/dev/null 2>&1 && : || :
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo "Test 10: fetch transient TLS handshake → success on attempt 2"
echo 0 >"$fake_state"
export GIT_FAKE_SEQ='1|fatal: unable to access: TLS handshake failed;0|'
out=$(git_fetch_retry --tags --force 2>/dev/null) && code=0 || code=$?
assert_eq "exit code" "0" "$code"
assert_eq "attempt count" "2" "$(<"$fake_state")"

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
