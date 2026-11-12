#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"

# --- Rate limit check (skip retry wrapper — local probe) ---
# Advisory only: a failed probe must not fail the job, but it must say why the
# budget check was skipped instead of hiding the error.
rl_err=$(mktemp)
if ! rl=$(gh api rate_limit --jq '.resources.core | "\(.remaining) \(.reset)"' 2>"$rl_err"); then
  echo "::warning::Rate-limit probe failed; continuing without the budget check: $(cat "$rl_err")"
  rl=""
fi
rm -f "$rl_err"
remaining=""
reset=""
if [ -n "$rl" ]; then
  read -r remaining reset <<<"$rl"
fi
if [ -n "$rl" ] && ! [[ "$remaining" =~ ^[0-9]+$ && "$reset" =~ ^[0-9]+$ ]]; then
  echo "::warning::Rate-limit probe returned unexpected output '$rl'; continuing without the budget check."
elif [ -n "$rl" ] && [ "$remaining" -lt "$RATE_LIMIT_THRESHOLD" ]; then
  wait=$(( reset - $(date +%s) + 5 ))
  if [ "$wait" -gt 0 ]; then
    echo "::warning::Rate limit low ($remaining remaining). Waiting ${wait}s for reset..."
    sleep "$wait"
  fi
fi

# --- Build dispatch request body ---
# workflow_dispatch inputs are strings on the wire (that is what
# `gh workflow run -f` sent), so coerce every value with tostring.
# `return_run_details: true` makes the API answer 200 with the created
# run's id instead of 204 No Content — that id is the only race-free way
# to identify OUR run. Earlier versions located the run by head_sha,
# which failed whenever someone pushed to $REF between resolve and
# dispatch (the child ran on the new head; shop run 42885354673).
if [ -z "$INPUTS_JSON" ]; then
  INPUTS_JSON='{}'
fi
body_file=$(mktemp)
if ! jq -n --arg ref "$REF" --argjson inputs "$INPUTS_JSON" \
    '{ref: $ref, inputs: ($inputs | map_values(tostring)), return_run_details: true}' >"$body_file"; then
  echo "::error::workflow-inputs is not a valid JSON object: $INPUTS_JSON"
  rm -f "$body_file"
  exit 1
fi

# --- Resolve REF to a SHA (diagnostics only) ---
# workflow_dispatch cannot be pinned to a SHA (`ref` must be a branch or
# tag), so the child runs on whatever $REF points at when GitHub
# processes the dispatch. We resolve it beforehand purely to warn when
# the child ended up on a different commit than the one we saw.
ref_err=$(mktemp)
ref_sha=$(retry_run gh api "repos/$REPOSITORY/commits/$REF" --jq .sha 2>"$ref_err") || true
if [ -z "$ref_sha" ]; then
  echo "::error::Could not resolve $REPOSITORY@$REF to a SHA before dispatch: $(cat "$ref_err")" >&2
  rm -f "$ref_err" "$body_file"
  exit 1
fi
rm -f "$ref_err"
dispatch_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Trigger workflow ---
# Wrap dispatch in `timeout` so a hanging TCP/TLS call fails fast with a
# diagnostic instead of stalling silently up to the job timeout. The
# notice breadcrumbs bracket the call so a future silent exit has a
# traceable last-known-good point in the log.
#
# Timeout budget must accommodate retry_run's full retry schedule:
#   4 attempts × ~30s worst-case per attempt + (5+15+45)s backoff = ~185s.
# Setting to 240s gives headroom; a hung TCP/TLS call still trips well
# inside the GitHub Actions job timeout.
echo "::notice::Dispatching $WORKFLOW to $REPOSITORY@$REF (sha=${ref_sha:0:8}, t=$dispatch_iso)..."
resp_file=$(mktemp)
set +e
BODY_FILE="$body_file" timeout 240 bash -c '
  source "$GITHUB_ACTION_PATH/../shared/retry.sh"
  retry_run gh api --method POST \
    "repos/$REPOSITORY/actions/workflows/$WORKFLOW/dispatches" \
    --input "$BODY_FILE"
' >"$resp_file"
code=$?
set -e
rm -f "$body_file"
if [ "$code" -eq 124 ]; then
  echo "::error::Dispatch of $WORKFLOW exceeded 240s — dispatch API exhausted retry attempts (HTTP 5xx) or hung on network I/O. The run may still have been created server-side; check $REPOSITORY actions for a recent run."
  rm -f "$resp_file"
  exit "$code"
fi
if [ "$code" -ne 0 ]; then
  echo "::error::Dispatch of $WORKFLOW failed (exit $code). Response: $(cat "$resp_file")"
  rm -f "$resp_file"
  exit "$code"
fi
echo "::notice::Dispatched $WORKFLOW"

# --- Capture run ID ---
run_id=""
if [ -s "$resp_file" ]; then
  if ! run_id=$(jq -r '.workflow_run_id // empty' "$resp_file"); then
    echo "::error::Dispatch of $WORKFLOW returned a malformed response: $(cat "$resp_file")"
    rm -f "$resp_file"
    exit 1
  fi
fi
rm -f "$resp_file"

if [ -z "$run_id" ]; then
  # Fallback for API hosts that ignore return_run_details (204, empty
  # body). Identify the run by workflow file + event=workflow_dispatch +
  # created_at >= dispatch_iso — deliberately NOT head_sha (see above).
  # If more than one run matches, we cannot tell which is ours: fail
  # loud rather than guess. Server-side query filters on this endpoint
  # are unreliable, so fetch the first page and filter with jq.
  echo "::warning::Dispatch API returned no workflow_run_id; falling back to locating the run by creation time."
  deadline=$(( $(date +%s) + 120 ))
  while [ -z "$run_id" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    list_err=$(mktemp)
    if ! ids=$(retry_run gh api "repos/$REPOSITORY/actions/workflows/$WORKFLOW/runs?per_page=20" \
        --jq "[.workflow_runs[] | select(.event == \"workflow_dispatch\" and .created_at >= \"$dispatch_iso\") | .id] | join(\" \")" \
        2>"$list_err"); then
      echo "::error::Listing runs of $WORKFLOW failed: $(cat "$list_err")"
      rm -f "$list_err"
      exit 1
    fi
    rm -f "$list_err"
    read -r -a candidates <<<"$ids"
    if [ "${#candidates[@]}" -gt 1 ]; then
      echo "::error::Ambiguous: ${#candidates[@]} workflow_dispatch runs of $WORKFLOW created since $dispatch_iso (${candidates[*]}); cannot tell which one this dispatch created."
      exit 1
    fi
    if [ "${#candidates[@]}" -eq 1 ]; then
      run_id="${candidates[0]}"
    else
      sleep 3
    fi
  done
fi

if [ -z "$run_id" ]; then
  echo "::error::Failed to locate dispatched run for $WORKFLOW@$REF (dispatched at $dispatch_iso) within 120s."
  echo "::error::The dispatch API returned no run id and no workflow_dispatch run of $WORKFLOW appeared. Possible causes: (1) GitHub API indexing exceeded 120s, (2) the dispatched workflow failed at start-up before being recorded."
  echo "::error::Check $REPOSITORY actions for runs of $WORKFLOW after $dispatch_iso and reconcile manually."
  exit 1
fi

# --- Diagnostics: did $REF move between resolve and dispatch? ---
# Read-after-write lag: straight after dispatch, GET /runs/{id} for the id
# the dispatch API just returned can 404 for a few seconds before GitHub
# makes the run visible (shop meta-prerelease-stage run 43009532540).
# retry_run treats 4xx as hard-fail, so poll here on HTTP 404 ONLY —
# every 3s, up to 60s — then fail loudly. Any other error fails at once.
run_err=$(mktemp)
read_deadline=$(( $(date +%s) + 60 ))
while :; do
  if run_sha=$(retry_run gh api "repos/$REPOSITORY/actions/runs/$run_id" --jq .head_sha 2>"$run_err"); then
    break
  fi
  if ! grep -q 'HTTP 404' "$run_err"; then
    echo "::error::Could not read dispatched run $run_id of $WORKFLOW: $(cat "$run_err")"
    rm -f "$run_err"
    exit 1
  fi
  if [ "$(date +%s)" -ge "$read_deadline" ]; then
    echo "::error::Dispatched run $run_id of $WORKFLOW in $REPOSITORY is still HTTP 404 after 60s. The dispatch API returned this run id but GitHub never made the run visible; check $REPOSITORY actions for run $run_id. Last error: $(cat "$run_err")"
    rm -f "$run_err"
    exit 1
  fi
  echo "::notice::Dispatched run $run_id of $WORKFLOW not visible yet (HTTP 404); retrying in 3s..."
  sleep 3
done
rm -f "$run_err"
if [ "$run_sha" != "$ref_sha" ]; then
  echo "::warning::$REF moved during dispatch: $WORKFLOW run $run_id is on ${run_sha:0:8}, not ${ref_sha:0:8} (resolved before dispatch). Proceeding with the run that was created."
fi

echo "::notice::Captured run $run_id for $WORKFLOW (sha=${run_sha:0:8})"
echo "run_id=$run_id" >> "$GITHUB_OUTPUT"
