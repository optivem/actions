#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"

echo "Waiting for run $RUN_ID (timeout: ${TIMEOUT_SECONDS}s)..."

DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))
# Read-after-write lag: a just-dispatched run can 404 for a few seconds (see
# trigger.sh). Tolerate consecutive 404s for this long, then fail loudly.
NOT_FOUND_WINDOW_SECONDS=60
not_found_since=""
poll_err=$(mktemp)
trap 'rm -f "$poll_err"' EXIT

# Poll the run's status in a loop bounded by TIMEOUT_SECONDS. A single failed
# poll (transient API/network outage — e.g. `dial tcp ...:443: i/o timeout`) is
# NON-FATAL: we warn and retry on the next interval, so an outage shorter than
# the overall timeout cannot fail a pipeline whose dispatched run actually
# succeeded. `retry_run` still absorbs short blips within each poll; this outer
# loop ties resilience to the documented timeout window instead of retry_run's
# fixed ~2.5-min budget. (Replaces a single streaming `gh run watch` whose
# `retry_run` cap gave up long before TIMEOUT_SECONDS was ever reached.)
#
# Only transient failures (5xx, network) are retried. HTTP 401/403 (bad token,
# missing permission, wrong repo) fail at once: retrying cannot fix them and
# would turn a misconfiguration into a long timeout. A GitHub *secondary* rate
# limit also answers 403, but it is a throttle, so it stays on the retry path.
# HTTP 404 is retried only within NOT_FOUND_WINDOW_SECONDS.
while :; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "::error::Workflow $WORKFLOW (run $RUN_ID) exceeded timeout of ${TIMEOUT_SECONDS}s. The upstream run may still be in progress — check manually before retrying."
    exit 124
  fi

  set +e
  result=$(retry_run gh run view "$RUN_ID" --repo "$REPOSITORY" \
    --json status,conclusion --jq '[.status, .conclusion] | @tsv' 2>"$poll_err")
  poll_code=$?
  set -e
  [ -s "$poll_err" ] && cat "$poll_err" >&2

  if [ "$poll_code" -ne 0 ]; then
    if grep -Eq 'HTTP 40[13]' "$poll_err" && ! grep -qi 'secondary rate limit' "$poll_err"; then
      echo "::error::Cannot read run $RUN_ID of $WORKFLOW in $REPOSITORY: access denied ($(grep -Eo 'HTTP 40[13][^(]*[^( ]' "$poll_err" | head -n1)). Check that the token passed to this action is valid and has 'actions: read' on $REPOSITORY, and that the repository name is correct."
      exit 1
    fi
    if grep -q 'HTTP 404' "$poll_err"; then
      now=$(date +%s)
      : "${not_found_since:=$now}"
      if [ $(( now - not_found_since )) -ge "$NOT_FOUND_WINDOW_SECONDS" ]; then
        echo "::error::Run $RUN_ID of $WORKFLOW in $REPOSITORY is still HTTP 404 after ${NOT_FOUND_WINDOW_SECONDS}s. Check that the run id and repository are correct and that the token can see $REPOSITORY."
        exit 1
      fi
    else
      not_found_since=""
    fi
    echo "::warning::Poll for run $RUN_ID failed transiently (exit $poll_code). Retrying in ${POLL_INTERVAL}s (timeout in $(( DEADLINE - $(date +%s) ))s)..."
    sleep "$POLL_INTERVAL"
    continue
  fi
  not_found_since=""

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
