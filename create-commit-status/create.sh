#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
if [ -n "$REF" ]; then
  SHA=$(gh_retry api "repos/${REPOSITORY}/commits/${REF}" --jq '.sha')
else
  SHA="$DEFAULT_SHA"
fi
TARGET_URL="${INPUT_TARGET_URL:-$DEFAULT_TARGET_URL}"
gh_retry api "repos/${REPOSITORY}/statuses/$SHA" \
  -f state="$STATE" \
  -f context="$CONTEXT" \
  -f description="$DESCRIPTION" \
  -f target_url="$TARGET_URL"
echo "Recorded status [$CONTEXT=$STATE] on commit $SHA${DESCRIPTION:+ ($DESCRIPTION)}" >> "$GITHUB_STEP_SUMMARY"
