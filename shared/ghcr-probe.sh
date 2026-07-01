#!/usr/bin/env bash
# ghcr-probe.sh — GHCR OCI token exchange + manifest probe.
#
# Source this file from any action.yml composite step that needs to probe
# whether a GHCR image tag exists, then call the two exported functions:
#
#   source "$GITHUB_ACTION_PATH/../shared/ghcr-probe.sh"
#   bearer_out=$(ghcr_bearer_for "$path" "$GH_TOKEN") || true
#   bearer=$(sed -n '1p' <<<"$bearer_out")
#   bearer_status=$(sed -n '2p' <<<"$bearer_out")
#   code=$(ghcr_probe_manifest "$manifest_url" "$bearer")
#
# Both functions are pure protocol primitives — they perform the OCI two-step
# token exchange + HEAD /v2/<path>/manifests/<tag> request and return the raw
# HTTP code (200/404/401/403, or another code after retries are exhausted).
# Callers own the interpretation: soft-fail vs hard-fail, mapping to boolean,
# surfacing error messages, deciding what to do on auth failure.
#
# Why OCI vs the GitHub Packages REST API: uniform shape across public/private
# images and user/org-owned repos. The Packages REST API has path-shape
# differences (/orgs/{org}/packages vs /users/{user}/packages) and no
# repo-scoped list endpoint — the OCI registry treats them all the same way.
#
# Retry: on transient HTTP codes (anything outside 200/404/401/403), retry up
# to 4 attempts with 5s → 15s → 45s backoff. After exhaustion, the last-seen
# code is returned (or "000" if every attempt failed at the network layer) so
# the caller can decide how to react.

_GHCR_PROBE_ATTEMPTS=4
_GHCR_PROBE_DELAYS=(5 15 45)
_GHCR_PROBE_ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

# ghcr_bearer_for PATH [TOKEN]
#
# Exchange a GitHub token for a GHCR OCI bearer scoped to read the given
# repository path (e.g. "optivem/shop/backend"). When TOKEN is empty, requests
# an anonymous bearer — works for public packages.
#
# Prints exactly two lines to stdout: the bearer token (empty on any failure)
# followed by the token-exchange HTTP status code ("000" if curl failed at the
# network layer, e.g. DNS/connection failure, before a response was received).
# Returns 0 only on a clean 200 with a present `.token` field; returns 1 for
# every other case, so the caller must branch on the second line to tell apart
# 200-with-missing-token (malformed response) from 401 (invalid/expired token),
# 403 (valid token, wrong scope), and any other code or network failure
# (indeterminate — treat as fail-hard, not retried).
ghcr_bearer_for() {
    local scope_path="$1"
    local token="${2:-}"
    local url="https://ghcr.io/token?service=ghcr.io&scope=repository:${scope_path}:pull"
    local response status body bearer

    if [ -n "$token" ]; then
        response=$(curl -sS -w '\n%{http_code}' -u "x-access-token:${token}" "$url") || response=$'\n000'
    else
        response=$(curl -sS -w '\n%{http_code}' "$url") || response=$'\n000'
    fi

    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    bearer=$(jq -r '.token // empty' <<<"$body" 2>/dev/null || true)

    printf '%s\n%s\n' "$bearer" "$status"

    [ "$status" = "200" ] && [ -n "$bearer" ]
}

# ghcr_probe_manifest URL BEARER
#
# Issue a HEAD /v2/<path>/manifests/<tag> with the OCI Accept header set and
# return the HTTP response code. Retries transient codes (anything outside
# 200/404/401/403) with 5s → 15s → 45s backoff, up to 4 attempts. After
# exhaustion, returns the last-seen code (or "000" if every attempt failed at
# the network layer).
ghcr_probe_manifest() {
    local url="$1"
    local bearer="$2"
    local attempt=1
    local code

    while (( attempt <= _GHCR_PROBE_ATTEMPTS )); do
        code=$(curl -sS -L -I -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $bearer" \
            -H "Accept: $_GHCR_PROBE_ACCEPT" \
            "$url" || echo "000")

        case "$code" in
            200|404|401|403) echo "$code"; return 0 ;;
        esac

        if (( attempt < _GHCR_PROBE_ATTEMPTS )); then
            local delay_idx=$(( attempt - 1 ))
            (( delay_idx >= ${#_GHCR_PROBE_DELAYS[@]} )) && delay_idx=$(( ${#_GHCR_PROBE_DELAYS[@]} - 1 ))
            echo "::notice::[ghcr-probe] attempt $attempt got HTTP $code for $url -- retrying in ${_GHCR_PROBE_DELAYS[$delay_idx]}s" >&2
            sleep "${_GHCR_PROBE_DELAYS[$delay_idx]}"
        fi
        (( attempt++ ))
    done

    echo "$code"
}
