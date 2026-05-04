#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

DESCRIPTION="${INPUT_DESCRIPTION:-Deploy of $REF}"

# Bracket each gh API call with breadcrumb notices so a silent exit
# (e.g. server-side 5xx with empty body) has a traceable last-known-good
# point in the log instead of looking like a 12-second silence followed
# by `exit 1`.
echo "::notice::Creating deployment for ${REPOSITORY} ref=${REF} environment=${ENVIRONMENT}..."
deployment_id=$(jq -nc \
  --arg ref "$REF" \
  --arg env "$ENVIRONMENT" \
  --arg desc "$DESCRIPTION" \
  '{ref: $ref, environment: $env, description: $desc, auto_merge: false, required_contexts: [], transient_environment: false, production_environment: false}' \
  | gh_retry api "repos/${REPOSITORY}/deployments" --input - --jq '.id')
if [ -z "$deployment_id" ] || [ "$deployment_id" = "null" ]; then
  echo "::error::POST repos/${REPOSITORY}/deployments returned no id (got: '${deployment_id}'). Cannot record status."
  exit 1
fi
echo "::notice::Created deployment id=${deployment_id}; recording state=${STATE}..."

gh_retry api "repos/${REPOSITORY}/deployments/${deployment_id}/statuses" \
  -X POST \
  -f state="$STATE" \
  -f description="$DESCRIPTION" >/dev/null
echo "::notice::Recorded deployment ${deployment_id} state=${STATE}"

echo "deployment-id=${deployment_id}" >> "$GITHUB_OUTPUT"
echo "Recorded deployment [${ENVIRONMENT}] state=${STATE} on ref ${REF}" >> "$GITHUB_STEP_SUMMARY"
