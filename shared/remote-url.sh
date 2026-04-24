#!/usr/bin/env bash
# remote-url.sh — compose authenticated remote git URLs.
#
# Source this file from any action.yml composite step that builds a remote URL
# from (token, host, repo), then call one of the two exported functions:
#
#   source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"
#   remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")
#   push_target=$(remote_push_target "$TOKEN" "$GIT_HOST" "$REPO")
#
# remote_query_url:
#   For read-only operations (git fetch, git ls-remote). When TOKEN is set,
#   embeds `x-access-token:<TOKEN>` in the URL so the remote accepts the fetch.
#   When TOKEN is empty, falls back to the unauthenticated public HTTPS URL —
#   correct for public repos and predictable for private (fetch simply fails).
#
# remote_push_target:
#   For writing operations (git push). When TOKEN is set, embeds the token in
#   the URL so the push authenticates regardless of persisted git config.
#   When TOKEN is empty, falls back to the literal string "origin" so the
#   push uses whatever credentials actions/checkout already persisted — the
#   common case when the caller relies on GITHUB_TOKEN + the default remote.

remote_query_url() {
    local token="$1" host="$2" repo="$3"
    if [ -n "$token" ]; then
        printf 'https://x-access-token:%s@%s/%s.git' "$token" "$host" "$repo"
    else
        printf 'https://%s/%s.git' "$host" "$repo"
    fi
}

remote_push_target() {
    local token="$1" host="$2" repo="$3"
    if [ -n "$token" ]; then
        printf 'https://x-access-token:%s@%s/%s.git' "$token" "$host" "$repo"
    else
        printf 'origin'
    fi
}
