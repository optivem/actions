#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"

echo "Waiting for run $RUN_ID (timeout: ${TIMEOUT_SECONDS}s)..."

DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

# Poll the run's status in a loop bounded by TIMEOUT_SECONDS. A single failed
# poll (transient API/network outage — e.g. `dial tcp ...:443: i/o timeout`) is
# NON-FATAL: we warn and retry on the next interval, so an outage shorter than
# the overall timeout cannot fail a pipeline whose dispatched run actually
# succeeded. `retry_run` still absorbs short blips within each poll; this outer
# loop ties resilience to the documented timeout window instead of retry_run's
# fixed ~2.5-min budget. (Replaces a single streaming `gh run watch` whose
# `retry_run` cap gave up long before TIMEOUT_SECONDS was ever reached.)
while :; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "::error::Workflow $WORKFLOW (run $RUN_ID) exceeded timeout of ${TIMEOUT_SECONDS}s. The upstream run may still be in progress — check manually before retrying."
    exit 124
  fi

  set +e
  result=$(retry_run gh run view "$RUN_ID" --repo "$REPOSITORY" \
    --json status,conclusion --jq '[.status, .conclusion] | @tsv')
  poll_code=$?
  set -e

  if [ "$poll_code" -ne 0 ]; then
    echo "::warning::Poll for run $RUN_ID failed transiently (exit $poll_code). Retrying in ${POLL_INTERVAL}s (timeout in $(( DEADLINE - $(date +%s) ))s)..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  status=${result%%$'\t'*}
  conclusion=${result#*$'\t'}

  if [ "$status" = "completed" ]; then
    if [ "$conclusion" = "success" ]; then
      echo "Run $RUN_ID completed successfully."
      exit 0
    fi
    echo "::error::Workflow $WORKFLOW (run $RUN_ID) completed with conclusion '$conclusion'."
    exit 1
  fi

  echo "Run $RUN_ID status='$status' (not yet completed), polling again in ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
done
