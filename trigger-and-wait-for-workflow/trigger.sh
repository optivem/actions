#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

# --- Rate limit check (skip retry wrapper — local probe) ---
remaining=$(gh api rate_limit --jq ".resources.core.remaining" 2>/dev/null || echo "999")
if [ "$remaining" -lt "$RATE_LIMIT_THRESHOLD" ]; then
  reset=$(gh api rate_limit --jq ".resources.core.reset" 2>/dev/null || echo "0")
  wait=$(( reset - $(date +%s) + 5 ))
  if [ "$wait" -gt 0 ]; then
    echo "::warning::Rate limit low ($remaining remaining). Waiting ${wait}s for reset..."
    sleep "$wait"
  fi
fi

# --- Build input flags ---
input_flags=""
if [ "$INPUTS_JSON" != "{}" ] && [ -n "$INPUTS_JSON" ]; then
  input_flags=$(echo "$INPUTS_JSON" | jq -r 'to_entries[] | "-f \(.key)=\(.value)"' | tr '\n' ' ')
fi

# --- Resolve REF to a SHA so we can disambiguate the dispatched run
# by head_sha. Without this, two parallel callers dispatching the same
# workflow on the same branch (or any concurrent push/cron event)
# could lead `gh run list --branch=main --limit 1` to return a
# sibling's run instead of ours. Resolved BEFORE dispatch — accept the
# tiny race where ref moves between resolve and dispatch (in practice,
# workflows protected by concurrency: groups serialise this).
ref_sha=$(gh api "repos/$REPOSITORY/commits/$REF" --jq .sha 2>/dev/null)
if [ -z "$ref_sha" ]; then
  echo "::error::Could not resolve $REPOSITORY@$REF to a SHA before dispatch"
  exit 1
fi
dispatch_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Trigger workflow ---
# Wrap dispatch in `timeout` so a hanging TCP/TLS call fails fast with a
# diagnostic instead of stalling silently up to the job timeout. The
# notice breadcrumbs bracket the call so a future silent exit has a
# traceable last-known-good point in the log.
#
# Timeout budget must accommodate gh_retry's full retry schedule:
#   4 attempts × ~30s worst-case per attempt + (5+15+45)s backoff = ~185s.
# Setting to 240s gives headroom; a hung TCP/TLS call still trips well
# inside the GitHub Actions job timeout.
echo "::notice::Dispatching $WORKFLOW to $REPOSITORY@$REF (sha=${ref_sha:0:8}, t=$dispatch_iso)..."
set +e
timeout 240 bash -c '
  source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"
  gh_retry workflow run "$WORKFLOW" \
    --repo "$REPOSITORY" \
    --ref "$REF" \
    '"$input_flags"'
'
code=$?
set -e
if [ "$code" -eq 124 ]; then
  echo "::error::Dispatch of $WORKFLOW exceeded 240s — gh workflow run exhausted gh_retry attempts (HTTP 5xx) or hung on network I/O. The run may still have been created server-side; check $REPOSITORY actions for a recent run."
  exit "$code"
fi
if [ "$code" -ne 0 ]; then
  echo "::error::Dispatch of $WORKFLOW failed (exit $code)."
  exit "$code"
fi
echo "::notice::Dispatched $WORKFLOW"

# --- Capture run ID by polling for the run we just dispatched ---
# Identification predicate: same workflow file + event=workflow_dispatch
# + head_sha matches resolved REF + created_at >= dispatch_iso.
# Server-side query filters on this endpoint are unreliable (the
# `branch`/`event`/`head_sha` GET parameters intermittently return
# empty even when matching runs exist), so we fetch the first page
# unfiltered and filter client-side with jq — that path has been
# observed reliable end-to-end. Polls until found or 120s deadline,
# then fails loud rather than coercing to an empty run id.
deadline=$(( $(date +%s) + 120 ))
run_id=""
while [ -z "$run_id" ] && [ "$(date +%s)" -lt "$deadline" ]; do
  run_id=$(gh api "repos/$REPOSITORY/actions/workflows/$WORKFLOW/runs?per_page=20" \
    --jq "[.workflow_runs[] | select(.event == \"workflow_dispatch\" and .head_sha == \"$ref_sha\" and .created_at >= \"$dispatch_iso\")] | sort_by(.created_at) | .[-1].id // empty" \
    2>/dev/null) || run_id=""
  if [ -z "$run_id" ]; then
    sleep 3
  fi
done

if [ -z "$run_id" ]; then
  echo "::error::Failed to locate dispatched run for $WORKFLOW@$REF (sha=${ref_sha:0:8}, dispatched at $dispatch_iso) within 120s."
  echo "::error::Possible causes: (1) GitHub API indexing exceeded 120s, (2) the dispatched workflow failed at start-up before being recorded, (3) ref moved between resolve and dispatch causing head_sha mismatch."
  echo "::error::Check $REPOSITORY actions for runs of $WORKFLOW after $dispatch_iso and reconcile manually."
  exit 1
fi

echo "::notice::Captured run $run_id for $WORKFLOW"
echo "run_id=$run_id" >> "$GITHUB_OUTPUT"
