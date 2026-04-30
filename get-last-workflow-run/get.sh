#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

# The default status="completed" filter prevents picking a sibling run
# that is still queued or in_progress as the "previous" run — its
# createdAt would be a future timestamp from the perspective of the
# artifact-freshness comparison, forcing a false skip when concurrent
# runs race (e.g. scheduled run + workflow_dispatch arriving within
# seconds of each other).
#
# The default conclusion="success" filter makes freshness gates
# compare against the last *successful* verification — failed runs do
# not count as "last verified", so the next trigger retries instead
# of skipping until artifacts change.
#
# The default limit covers concurrent triggers (push + schedule +
# dispatch arriving together) plus headroom for recent failures or
# in-progress siblings that get filtered out before the last match.
timestamp=$(gh_retry run list \
  --repo "${REPOSITORY}" \
  --workflow "$WORKFLOW_NAME" \
  --limit "${LIMIT}" \
  --json databaseId,createdAt,status,conclusion \
  2>/dev/null \
  | jq -r --arg cur "$EXCLUDE_RUN_ID" --arg status "$STATUS" --arg conclusion "$CONCLUSION" \
       '[.[]
         | select(($status == "") or (.status == $status))
         | select(($conclusion == "") or (.conclusion == $conclusion))
         | select(($cur == "") or (.databaseId != ($cur | tonumber)))
        ][0].createdAt // ""')

if [[ -z "$timestamp" ]]; then
  echo "No previous run matching status='${STATUS}' conclusion='${CONCLUSION}' found for workflow '$WORKFLOW_NAME'."
else
  echo "Last matching run (status='${STATUS}' conclusion='${CONCLUSION}'): $timestamp"
fi

echo "timestamp=$timestamp" >> "$GITHUB_OUTPUT"
