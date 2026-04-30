#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

if [[ -z "$HEAD_SHA" ]]; then
  echo "::error::head-sha is empty"
  exit 1
fi

echo "Head SHA: $HEAD_SHA"
echo "Commit SHA (matched against description): $COMMIT_SHA"
echo "Status context: $STATUS_CONTEXT"

if ! statuses=$(gh_retry api "repos/${REPOSITORY}/commits/${HEAD_SHA}/statuses" --paginate 2>&1); then
  echo "::error::Could not fetch commit statuses for ${REPOSITORY}@${HEAD_SHA} after gh_retry exhaustion. Indeterminate — exiting 1 rather than coercing to exists=false. Details: $statuses"
  exit 1
fi

match_created_at=$(echo "$statuses" | jq -r --arg ctx "$STATUS_CONTEXT" --arg sha "$COMMIT_SHA" '
  map(select(.context == $ctx and .description == $sha and .state == "success"))
  | .[0].created_at // ""
')

if [[ -n "$match_created_at" ]]; then
  echo "Matching success status found, created at $match_created_at — exists=true"
  {
    echo "exists=true"
    echo "created-at=$match_created_at"
  } >> "$GITHUB_OUTPUT"
else
  echo "No matching success status — exists=false"
  {
    echo "exists=false"
    echo "created-at="
  } >> "$GITHUB_OUTPUT"
fi
