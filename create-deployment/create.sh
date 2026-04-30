#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

DESCRIPTION="${INPUT_DESCRIPTION:-Deploy of $REF}"

deployment_id=$(jq -nc \
  --arg ref "$REF" \
  --arg env "$ENVIRONMENT" \
  --arg desc "$DESCRIPTION" \
  '{ref: $ref, environment: $env, description: $desc, auto_merge: false, required_contexts: [], transient_environment: false, production_environment: false}' \
  | gh_retry api "repos/${REPOSITORY}/deployments" --input - --jq '.id')

gh_retry api "repos/${REPOSITORY}/deployments/${deployment_id}/statuses" \
  -X POST \
  -f state="$STATE" \
  -f description="$DESCRIPTION" >/dev/null

echo "deployment-id=${deployment_id}" >> "$GITHUB_OUTPUT"
echo "Recorded deployment [${ENVIRONMENT}] state=${STATE} on ref ${REF}" >> "$GITHUB_STEP_SUMMARY"
