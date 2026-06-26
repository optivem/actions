#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"
echo "Waiting for $WORKFLOW (commit: $COMMIT_SHA, timeout: ${TIMEOUT_SECONDS}s)..."

DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

attempt=1
while [ "$attempt" -le "$MAX_DISCOVERY_ATTEMPTS" ]; do
  now=$(date +%s)
  if [ "$now" -ge "$DEADLINE" ]; then
    echo "::error::Timed out after ${TIMEOUT_SECONDS}s waiting for $WORKFLOW to appear for commit $COMMIT_SHA (discovery phase)."
    exit 124
  fi

  # --- Rate limit check (skip retry wrapper — local probe) ---
  remaining=$(gh api rate_limit --jq ".resources.core.remaining" 2>/dev/null || echo "999")
  if [ "$remaining" -lt "$RATE_LIMIT_THRESHOLD" ]; then
    reset=$(gh api rate_limit --jq ".resources.core.reset" 2>/dev/null || echo "0")
    wait_secs=$(( reset - $(date +%s) + 5 ))
    if [ "$wait_secs" -gt 0 ]; then
      echo "::warning::Rate limit low ($remaining remaining). Waiting ${wait_secs}s for reset..."
      sleep "$wait_secs"
    fi
  fi

  # --- Find run by commit SHA ---
  run_id=$(retry_run gh run list \
    --workflow="$WORKFLOW" \
    --repo "$REPOSITORY" \
    --limit 5 \
    --json databaseId,headSha \
    --jq "[.[] | select(.headSha == \"$COMMIT_SHA\")] | .[0].databaseId")

  if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
    echo "Found run $run_id on attempt $attempt, polling for completion..."
    echo "run_id=$run_id" >> $GITHUB_OUTPUT

    # Poll the run's status until completion or the overall DEADLINE. A single
    # failed poll (transient API/network outage — e.g. `dial tcp ...:443: i/o
    # timeout`) is NON-FATAL: warn and retry on the next interval, so an outage
    # shorter than the timeout cannot fail a run that actually succeeded.
    # (Replaces a streaming `gh run watch` whose `retry_run` cap gave up long
    # before TIMEOUT_SECONDS was ever reached.)
    while :; do
      if [ "$(date +%s)" -ge "$DEADLINE" ]; then
        echo "::error::Workflow $WORKFLOW (run $run_id) exceeded timeout of ${TIMEOUT_SECONDS}s."
        exit 124
      fi

      set +e
      result=$(retry_run gh run view "$run_id" --repo "$REPOSITORY" \
        --json status,conclusion --jq '[.status, .conclusion] | @tsv')
      poll_code=$?
      set -e

      if [ "$poll_code" -ne 0 ]; then
        echo "::warning::Poll for run $run_id failed transiently (exit $poll_code). Retrying in ${WATCH_INTERVAL}s (timeout in $(( DEADLINE - $(date +%s) ))s)..."
        sleep "$WATCH_INTERVAL"
        continue
      fi

      status=${result%%$'\t'*}
      conclusion=${result#*$'\t'}

      if [ "$status" = "completed" ]; then
        if [ "$conclusion" = "success" ]; then
          echo "Run $run_id completed successfully."
          exit 0
        fi
        echo "::error::Workflow $WORKFLOW (run $run_id) completed with conclusion '$conclusion'."
        exit 1
      fi

      echo "Run $run_id status='$status' (not yet completed), polling again in ${WATCH_INTERVAL}s..."
      sleep "$WATCH_INTERVAL"
    done
  fi

  echo "Run not found yet (attempt $attempt/$MAX_DISCOVERY_ATTEMPTS), waiting ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
  attempt=$((attempt + 1))
done

echo "::error::Workflow $WORKFLOW did not appear for commit $COMMIT_SHA after $MAX_DISCOVERY_ATTEMPTS discovery attempts (total wait ~$((MAX_DISCOVERY_ATTEMPTS * POLL_INTERVAL))s). Check that the dispatch succeeded and that the commit SHA is correct."
exit 1
