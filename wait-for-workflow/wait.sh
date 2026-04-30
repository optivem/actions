#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
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
  run_id=$(gh_retry run list \
    --workflow="$WORKFLOW" \
    --repo "$REPOSITORY" \
    --limit 5 \
    --json databaseId,headSha \
    --jq "[.[] | select(.headSha == \"$COMMIT_SHA\")] | .[0].databaseId")

  if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
    echo "Found run $run_id on attempt $attempt, watching..."
    echo "run_id=$run_id" >> $GITHUB_OUTPUT
    export RUN_ID="$run_id"
    remaining_secs=$(( DEADLINE - $(date +%s) ))
    if [ "$remaining_secs" -le 0 ]; then
      echo "::error::Timed out after ${TIMEOUT_SECONDS}s before watch could start for run $run_id."
      exit 124
    fi
    set +e
    timeout "$remaining_secs" bash -c '
      source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
      gh_retry run watch "$RUN_ID" --repo "$REPOSITORY" --exit-status --interval "$WATCH_INTERVAL"
    '
    code=$?
    set -e
    if [ "$code" -eq 124 ]; then
      echo "::error::Workflow $WORKFLOW (run $run_id) exceeded timeout of ${TIMEOUT_SECONDS}s."
    fi
    exit "$code"
  fi

  echo "Run not found yet (attempt $attempt/$MAX_DISCOVERY_ATTEMPTS), waiting ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
  attempt=$((attempt + 1))
done

echo "::error::Workflow $WORKFLOW did not appear for commit $COMMIT_SHA after $MAX_DISCOVERY_ATTEMPTS discovery attempts (total wait ~$((MAX_DISCOVERY_ATTEMPTS * POLL_INTERVAL))s). Check that the dispatch succeeded and that the commit SHA is correct."
exit 1
