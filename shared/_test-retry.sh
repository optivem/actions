#!/usr/bin/env bash
# Local smoke-test harness for shared/retry.sh.
#
# Exercises the unified transient + hard-fail regex against representative
# stderr phrasings from each of the four original tool wrappers (gh, docker,
# sonar, git) to confirm the union covers them all. Runs by shadowing a
# `faketool` binary on PATH that returns a scripted sequence of exit codes
# and stderr messages. Not wired into CI — run manually:
#
#   bash shared/_test-retry.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fake_dir=$(mktemp -d -t retry-test.XXXXXX)
fake_state="$fake_dir/state"
fake_bin="$fake_dir/faketool"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
counter=0
if [[ -f "$FAKE_STATE" ]]; then
    counter=$(<"$FAKE_STATE")
fi
IFS=';' read -ra seq <<<"$FAKE_SEQ"
idx=$counter
if (( idx >= ${#seq[@]} )); then
    idx=$(( ${#seq[@]} - 1 ))
fi
entry="${seq[$idx]}"
code="${entry%%|*}"
# Entry format: code|stderr  or  code|stderr|stdout (stdout field optional).
# Parsed pipe-safely so the optional 3rd field is backward-compatible with
# the existing 2-field cases.
rest="${entry#*|}"
[[ "$rest" == "$entry" ]] && rest=""
stderr="${rest%%|*}"
stdout_extra=""
[[ "$rest" == *"|"* ]] && stdout_extra="${rest#*|}"
if [[ -n "$stderr" ]]; then
    printf '%s\n' "$stderr" >&2
fi
if [[ -n "$stdout_extra" ]]; then
    printf '%s\n' "$stdout_extra"
fi
printf 'fake-stdout-%d\n' "$counter"
echo $(( counter + 1 )) >"$FAKE_STATE"
exit "$code"
FAKE
chmod +x "$fake_bin"
export FAKE_STATE="$fake_state"

trap 'rm -rf "$fake_dir"' EXIT

export PATH="$fake_dir:$PATH"

# shellcheck source=./retry.sh
source "$HERE/retry.sh"
_RETRY_DELAYS=(0 0 0)

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

run_case() {
    local label="$1" seq="$2" expected_code="$3" expected_attempts="$4"
    echo "$label"
    echo 0 >"$fake_state"
    export FAKE_SEQ="$seq"
    local code=0
    retry_run faketool arg >/dev/null 2>&1 || code=$?
    assert_eq "exit code" "$expected_code" "$code"
    assert_eq "attempt count" "$expected_attempts" "$(<"$fake_state")"
}

# Transient: each phrasing should trigger retry and succeed on attempt 3.
run_case "gh transient: HTTP 502 → 502 → 0 (3 attempts)" \
    '1|HTTP 502: Bad Gateway;1|HTTP 502: Bad Gateway;0|' 0 3

run_case "docker transient: context deadline exceeded → 0 (2 attempts)" \
    '1|context deadline exceeded;0|' 0 2

run_case "docker transient: daemon registry unknown → 0 (2 attempts)" \
    '1|Error response from daemon: Get "https://registry-1.docker.io/v2/": unknown:;0|' 0 2

run_case "sonar transient: Error 503 on https:// → 0 (2 attempts)" \
    '1|Error 503 on https://sonarcloud.io;0|' 0 2

run_case "sonar transient: Endpoint request timed out → 0 (2 attempts)" \
    '1|Endpoint request timed out;0|' 0 2

run_case "sonar transient: JS bootstrapper JRE-provisioning 403 → 0 (2 attempts)" \
    '1|[ERROR] Bootstrapper: An error occurred: AxiosError: Request failed with status code 403;0|' 0 2

run_case "sonar transient: axios 503 phrasing → 0 (2 attempts)" \
    '1|AxiosError: Request failed with status code 503;0|' 0 2

# stdout-stream classification: the SonarScanner JS bootstrapper logs its
# failure to stdout, not stderr. The signature must still be detected there.
run_case "sonar transient on stdout: bootstrapper 403 → 0 (2 attempts)" \
    '1||[ERROR] Bootstrapper: An error occurred: AxiosError: Request failed with status code 403;0|' 0 2

# Force-retry override: the Gradle Sonar plugin's JRE-provisioning 403 prints
# the literal `HTTP 403 Forbidden`, which matches the hard-fail list — but the
# `_RETRY_FORCE_RETRY` override (`/analysis/jres`, `Failed to query JRE
# metadata`) must reclaim it as transient and retry.
run_case "sonar transient: Gradle JRE-metadata 403 → 0 (2 attempts)" \
    '1|Failed to query JRE metadata: GET https://api.sonarcloud.io/analysis/jres?os=linux&arch=x86_64 failed with HTTP 403 Forbidden. Please check the property sonar.token or the environment variable SONAR_TOKEN.;0|' 0 2

# Same JRE-provisioning 403, but from the standalone sonar-scanner-cli: a
# different endpoint (`scanner.sonarcloud.io/jres/`) and phrasing (`HttpException
# ... failed with HTTP 403 Forbidden`) that the `/analysis/jres` clause misses.
# The `scanner.sonarcloud.io/jres` clause must reclaim it as transient.
run_case "sonar transient: scanner-cli JRE-download 403 → 0 (2 attempts)" \
    '1|org.sonarsource.scanner.lib.internal.http.HttpException: GET https://scanner.sonarcloud.io/jres/OpenJDK21U-jre_x64_linux_hotspot_21.0.9_10.tar.gz failed with HTTP 403 Forbidden;0|' 0 2

# Transient CDN binary-download 403 from binaries.sonarsource.com (the original
# trigger of this plan). `HTTP 403 Forbidden` matches the hard-fail list, so the
# `binaries.sonarsource.com` force-retry clause must reclaim it as transient.
run_case "sonar transient: scanner-cli binary-download 403 → 0 (2 attempts)" \
    '1|org.sonarsource.scanner.lib.internal.http.HttpException: GET https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-8.0.1.6346-linux-x64.zip failed with HTTP 403 Forbidden;0|' 0 2

# GHCR reports a secondary rate limit using authz vocabulary — `denied:
# permission_denied` + `HTTP status code 403 "Forbidden"` — which matches the
# hard-fail list. The `exceeded a secondary rate limit` force-retry clause must
# reclaim it as transient, or a throttled `docker compose pull` dies with zero
# attempts (gh-optivem run 31365614953).
run_case "docker transient: GHCR secondary rate-limit 403 → 0 (2 attempts)" \
    '1|error pulling image configuration: download failed after attempts=1: denied: permission_denied: Error from intermediary with HTTP status code 403 "Forbidden" - with-body: {"message": "You have exceeded a secondary rate limit. Please wait a few minutes before you try again."};0|' 0 2

run_case "git transient: Could not resolve host → 0 (2 attempts)" \
    '1|fatal: unable to access: Could not resolve host github.com;0|' 0 2

# git phrases *any* server-side push rejection as `[remote rejected] <ref> ->
# <ref> (<reason>)`, which collides with the `! \[remote rejected\]` hard-fail
# pattern even when <reason> is itself a transient 5xx. The force-retry
# override must reclaim it (gh-optivem run 31709529616, publish-tag/tag.sh:38).
run_case "git transient: remote rejected (Internal Server Error) → 0 (2 attempts)" \
    '1|! [remote rejected] v1.0.187 -> v1.0.187 (Internal Server Error);0|' 0 2

run_case "git transient: remote rejected (Bad Gateway) → 0 (2 attempts)" \
    '1|! [remote rejected] main -> main (Bad Gateway);0|' 0 2

# jq's generic parse-failure text for a truncated/empty gh api response body —
# a transient network symptom, not evidence of a real API/auth problem
# (gh-optivem run 31709529616, create-deployment/create.sh:18).
run_case "gh transient: unexpected end of JSON input → 0 (2 attempts)" \
    '1|jq: error (at <unknown>): unexpected end of JSON input;0|' 0 2

run_case "git transient: RPC failed ... HTTP 503 → 0 (2 attempts)" \
    '1|error: RPC failed -- HTTP 503 curl 22 The requested URL returned error 503;0|' 0 2

run_case "gh transient: Something went wrong while executing your query → 0 (2 attempts)" \
    '1|GraphQL: Something went wrong while executing your query;0|' 0 2

# Hard-fail: pass through after 1 attempt, preserve non-zero exit.
run_case "gh hard-fail: HTTP 404 → 1 attempt" \
    '1|HTTP 404: Not Found' 1 1

run_case "gh hard-fail: HTTP 403 rate limit → 1 attempt" \
    '1|HTTP 403: API rate limit exceeded' 1 1

run_case "docker hard-fail: manifest unknown → 1 attempt" \
    '1|manifest unknown: manifest unknown' 1 1

run_case "docker hard-fail: denied: requested access → 1 attempt" \
    '1|denied: requested access to the resource is denied' 1 1

# The secondary-rate-limit override is narrow: a genuine GHCR authz denial uses
# the same `denied: permission_denied` / `Forbidden` vocabulary but carries no
# rate-limit wording, so it must still fail fast rather than burn 5 attempts.
run_case "docker hard-fail: GHCR permission_denied without rate-limit wording → 1 attempt" \
    '1|error pulling image configuration: download failed after attempts=1: denied: permission_denied: Error from intermediary with HTTP status code 403 "Forbidden"' 1 1

run_case "sonar hard-fail: Project key X does not exist → 1 attempt" \
    '1|ERROR: Project key gh-optivem does not exist on this server' 1 1

run_case "sonar hard-fail: Not authorized → 1 attempt" \
    '1|ERROR: Not authorized. Analyzing this project requires authentication' 1 1

# Override is narrow: a genuine auth 403 that is NOT the JRE-provisioning call
# must still fail fast (the force-retry override only reclaims /analysis/jres).
run_case "sonar hard-fail: analysis-submission HTTP 403 Forbidden → 1 attempt" \
    '1|ERROR: Failed to upload report: HTTP 403 Forbidden' 1 1

run_case "git hard-fail: remote rejected → 1 attempt" \
    '1|! [remote rejected] main -> main (pre-receive hook declined)' 1 1

run_case "git hard-fail: repository not found → 1 attempt" \
    '1|fatal: repository foo/bar not found' 1 1

# Exhaustion: 4 straight transient failures → exhausts retries.
run_case "exhaustion: 4 × HTTP 502 → 4 attempts, non-zero" \
    '1|HTTP 502;1|HTTP 502;1|HTTP 502;1|HTTP 502' 1 4

# Disable bypass.
echo "RETRY_DISABLE=1 bypasses retry"
echo 0 >"$fake_state"
export FAKE_SEQ='1|HTTP 502;0|'
RETRY_DISABLE=1 retry_run faketool arg >/dev/null 2>&1 || :
assert_eq "attempt count" "1" "$(<"$fake_state")"

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
