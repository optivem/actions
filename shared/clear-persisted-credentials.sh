#!/usr/bin/env bash
# clear-persisted-credentials.sh — remove credentials persisted by actions/checkout.
#
# Source this file from any action.yml composite step that performs a git push
# via a URL-embedded token, then call `clear_persisted_credentials "$GIT_HOST"`
# before the push:
#
#   source "$GITHUB_ACTION_PATH/../shared/clear-persisted-credentials.sh"
#   clear_persisted_credentials "$GIT_HOST"
#   git push "$push_target" "$TAG"
#
# actions/checkout persists GITHUB_TOKEN differently by version: @v5 and earlier
# use http.<host>.extraheader; @v6 uses includeIf.gitdir:<path>.path pointing
# to a credentials config file. We clear both so the subsequent git push uses
# only the URL-embedded token passed by the caller — not whatever happens to
# be baked into local config from an earlier step.

clear_persisted_credentials() {
    local host="$1"
    git config --local --unset-all "http.https://${host}/.extraheader" 2>/dev/null || true
    while IFS= read -r key; do
        [ -n "$key" ] && git config --local --unset-all "$key" 2>/dev/null || true
    done < <(git config --local --name-only --get-regexp '^includeIf\.gitdir:' 2>/dev/null || true)
}
