#!/usr/bin/env bash
# retry.sh — unified retry wrapper for any shell command that hits an external
# service (gh CLI, docker registry, sonarscanner, git push/fetch, etc.).
#
# Used by the `optivem/actions/retry@v1` composite. Replaces the four
# tool-specific wrappers (gh-retry.sh, docker-retry.sh, sonar-retry.sh,
# git-retry.sh) — the transient + hard-fail regexes below are the union of
# all four, deduplicated. Concepts match across tools; only the specific
# phrasings differ, and the union is strictly broader without false-positive
# collisions (e.g. sonar output never contains `manifest unknown`).
#
# Usage:
#
#   source "$GITHUB_ACTION_PATH/../shared/retry.sh"
#   retry_run gh api repos/$owner/$repo/releases
#   retry_run docker pull node:22-alpine
#   retry_run bash ./run-sonar.sh
#   retry_run git push origin "$TAG"
#
# Behaviour: 4 attempts with 5s → 15s → 45s backoff. On HTTP 5xx, network
# blips, TLS/DNS errors, or known transient phrases across gh/docker/sonar/
# git tools — retry. On HTTP 4xx, auth errors, "not found" responses, or
# known hard-fail patterns — pass through immediately preserving exit code
# so callers using rc as a probe keep working.
#
# Set `RETRY_DISABLE=1` to bypass the retry loop entirely.

# shellcheck source=./retry-core.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retry-core.sh"

_RETRY_ATTEMPTS=4
_RETRY_DELAYS=(5 15 45)

# Union of transient patterns from gh-retry, docker-retry, sonar-retry,
# git-retry. Deduplicated; broader phrasings absorb narrower ones (e.g.
# `HTTP 5[0-9][0-9]` covers `HTTP 502|503|504` from git-retry).
# shellcheck disable=SC2034  # referenced via grep -E
_RETRY_RETRYABLE='HTTP 5[0-9][0-9]|Error 5[0-9][0-9] on https://|received unexpected HTTP status:? 5[0-9][0-9]|RPC failed.*HTTP 5[0-9][0-9]|Internal Server Error|Bad Gateway|Service Unavailable|Gateway Timeout|server error|Something went wrong while executing your query|Endpoint request timed out|context deadline exceeded|Client\.Timeout|Operation timed out|timeout|timed out|i/o timeout|net/http: TLS handshake timeout|connection reset|Connection reset by peer|connection refused|\bEOF\b|unexpected EOF|was closed|http2: server sent GOAWAY|TLS handshake|tls:.*handshake|server certificate verification failed|temporary failure in name resolution|no such host|Could not resolve host|unable to access|Error response from daemon: Get "[^"]+": unknown'

# Union of hard-fail patterns. `HTTP 4[0-9][0-9]` absorbs explicit 401/403
# from sonar/git. Tool-specific phrasings retained because some appear
# without an HTTP code (docker `manifest unknown`, sonar `Project key ... does
# not exist`, git `pre-receive hook declined`).
# shellcheck disable=SC2034
_RETRY_HARD_FAIL='HTTP 4[0-9][0-9]|HTTP 403.*rate limit|[Uu]nauthorized|Forbidden|Not authorized|Permission denied|denied: permission|denied: requested access|requested access to the resource is denied|insufficient_scope|manifest unknown|name unknown|repository name not known|Project key .* does not exist|Project .* not found|repository .* not found|! \[remote rejected\]|pre-receive hook declined|fatal: protocol|fatal: bad refspec'

retry_run() {
    if [[ "${RETRY_DISABLE:-0}" == "1" ]]; then
        "$@"
        return $?
    fi
    _RETRY_CORE_ATTEMPTS="$_RETRY_ATTEMPTS"
    _RETRY_CORE_DELAYS=("${_RETRY_DELAYS[@]}")
    retry_with_policy "$_RETRY_RETRYABLE" "$_RETRY_HARD_FAIL" retry -- "$@"
}
