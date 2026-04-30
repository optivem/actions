#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
if [ -n "$STATE_FILTER" ]; then
  JQ="[.[] | select(.context==\"$CONTEXT\" and .state==\"$STATE_FILTER\")][0]"
else
  JQ="[.[] | select(.context==\"$CONTEXT\")][0]"
fi
STATUS_JSON=$(gh_retry api "repos/$REPO/commits/$SHA/statuses" --jq "$JQ")
if [ -z "$STATUS_JSON" ] || [ "$STATUS_JSON" = "null" ]; then
  echo "description=" >> "$GITHUB_OUTPUT"
  echo "state=" >> "$GITHUB_OUTPUT"
  echo "target-url=" >> "$GITHUB_OUTPUT"
  echo "No ${STATE_FILTER:+$STATE_FILTER }commit status with context '$CONTEXT' found on $REPO commit $SHA" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
DESCRIPTION=$(echo "$STATUS_JSON" | jq -r '.description // ""')
STATE=$(echo "$STATUS_JSON" | jq -r '.state // ""')
TARGET_URL=$(echo "$STATUS_JSON" | jq -r '.target_url // ""')
echo "description=$DESCRIPTION" >> "$GITHUB_OUTPUT"
echo "state=$STATE" >> "$GITHUB_OUTPUT"
echo "target-url=$TARGET_URL" >> "$GITHUB_OUTPUT"
echo "Read status [$CONTEXT=$STATE] from commit $SHA${DESCRIPTION:+ ($DESCRIPTION)}" >> "$GITHUB_STEP_SUMMARY"
