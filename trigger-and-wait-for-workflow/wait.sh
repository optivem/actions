#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for run $RUN_ID (timeout: ${TIMEOUT_SECONDS}s)..."
set +e
timeout "$TIMEOUT_SECONDS" bash -c '
  source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
  gh_retry run watch "$RUN_ID" \
    --repo "$REPOSITORY" \
    --exit-status \
    --interval "$POLL_INTERVAL"
'
code=$?
set -e
if [ "$code" -eq 124 ]; then
  echo "::error::Workflow $WORKFLOW (run $RUN_ID) exceeded timeout of ${TIMEOUT_SECONDS}s. The upstream run may still be in progress — check manually before retrying."
fi
exit "$code"
