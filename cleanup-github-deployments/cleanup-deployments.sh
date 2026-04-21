#!/usr/bin/env bash
#
# cleanup-deployments.sh — delete superseded GitHub deployments.
#
# Mirrors cleanup-prereleases logic, adapted for deployments:
#
# Scenario 1 — Released versions (final tag vX.Y.Z exists):
#   - Immediately delete deployments whose SHA corresponds to any
#     vX.Y.Z-rc.* tag (bypassing keep-count and retention)
#
# Scenario 2 — Superseded per environment (count cap + retention floor):
#   - For each environment, keep the newest KEEP_COUNT deployments
#   - Anything beyond the cap is deleted only if also older than
#     RETENTION_DAYS
#
# GitHub requires a deployment to be inactive before deletion, so each
# deployment gets a new "inactive" status created before the DELETE call.
#
# IMPORTANT: run this action BEFORE cleanup-prereleases — Scenario 1
# relies on the RC git tags still being present to resolve SHAs.

set -euo pipefail
shopt -s nocasematch

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../shared/gh-retry.sh
source "$SCRIPT_DIR/../shared/gh-retry.sh"

: "${KEEP_COUNT:=3}"
: "${RETENTION_DAYS:=30}"
: "${PROTECTED_ENVIRONMENTS:=*-production,production}"
: "${DELETE_DELAY_SECONDS:=10}"
: "${RATE_LIMIT_THRESHOLD:=50}"
: "${DRY_RUN:=false}"
: "${REPOSITORY:=${GITHUB_REPOSITORY:-}}"

if [[ -z "$REPOSITORY" ]]; then
  echo "::error::REPOSITORY env var is required"
  exit 1
fi

# Build protected-environment pattern array (comma-separated, trimmed).
IFS=',' read -r -a protected_patterns_raw <<<"$PROTECTED_ENVIRONMENTS"
protected_patterns=()
for p in "${protected_patterns_raw[@]}"; do
  trimmed=$(echo "$p" | xargs)
  [[ -n "$trimmed" ]] && protected_patterns+=("$trimmed")
done

is_protected() {
  local env_name="$1"
  [[ -z "$env_name" ]] && return 1
  local pat
  for pat in "${protected_patterns[@]}"; do
    # shellcheck disable=SC2053
    [[ "$env_name" == $pat ]] && return 0
  done
  return 1
}

wait_for_rate_limit_budget() {
  (( RATE_LIMIT_THRESHOLD <= 0 )) && return
  local remaining reset now wait_secs
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "")
  [[ -z "$remaining" ]] && return
  (( remaining >= RATE_LIMIT_THRESHOLD )) && return
  reset=$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null || echo "")
  [[ -z "$reset" ]] && return
  now=$(date +%s)
  wait_secs=$((reset - now + 5))
  (( wait_secs <= 0 )) && return
  echo "::warning::Rate limit low ($remaining remaining, threshold $RATE_LIMIT_THRESHOLD). Waiting ${wait_secs}s for reset..."
  sleep "$wait_secs"
}

cutoff_epoch=$(date -u -d "$RETENTION_DAYS days ago" +%s)

echo "========================================"
echo "  Deployment Cleanup"
echo "========================================"
echo
echo "Repository:             $REPOSITORY"
echo "Keep Count:             $KEEP_COUNT"
echo "Retention Days:         $RETENTION_DAYS"
if (( ${#protected_patterns[@]} > 0 )); then
  echo "Protected Environments: $(IFS=,; echo "${protected_patterns[*]}")"
else
  echo "Protected Environments: (none)"
fi
echo "Delete Delay:           ${DELETE_DELAY_SECONDS}s"
if (( RATE_LIMIT_THRESHOLD > 0 )); then
  echo "Rate-Limit Threshold:   $RATE_LIMIT_THRESHOLD"
else
  echo "Rate-Limit Threshold:   (disabled)"
fi
echo "Dry Run:                $DRY_RUN"
echo

# ── Step 1: Categorize tags (local, no API calls) ───────────────────
echo "Categorizing tags..."

declare -A final_releases    # "1.0.0" -> "v1.0.0"
declare -A prerelease_tags   # "1.0.0" -> "v1.0.0-rc.1 v1.0.0-rc.2"

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  if [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    final_releases[${BASH_REMATCH[1]}]="$tag"
  elif [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-[a-zA-Z]+\.[0-9]+$ ]]; then
    version="${BASH_REMATCH[1]}"
    existing="${prerelease_tags[$version]:-}"
    prerelease_tags[$version]="${existing:+$existing }$tag"
  fi
done < <(git tag -l "v*")

echo "  Final releases:  ${#final_releases[@]}"
echo "  RC versions:     ${#prerelease_tags[@]}"

# ── Step 2: Build set of "released-RC SHAs" ─────────────────────────
declare -A released_rc_shas    # "<sha>" -> "<rc-tag>"

for version in "${!final_releases[@]}"; do
  rc_list="${prerelease_tags[$version]:-}"
  [[ -z "$rc_list" ]] && continue
  for rc_tag in $rc_list; do
    sha=$(git rev-list -n 1 "$rc_tag" 2>/dev/null || true)
    if [[ -n "$sha" ]]; then
      released_rc_shas[$sha]="$rc_tag"
    fi
  done
done
echo "  Released-RC SHAs: ${#released_rc_shas[@]}"
echo

# ── Step 3: Fetch all deployments (paginated) ───────────────────────
echo "Fetching all deployments..."

# --paginate concatenates JSON arrays; `jq -s 'add'` merges into one array.
deployments_json=$(gh_retry api "/repos/$REPOSITORY/deployments" --paginate 2>/dev/null | jq -s 'add // []' || echo '[]')

total=$(jq 'length' <<<"$deployments_json")
if (( total == 0 )); then
  echo "  No deployments found"
  exit 0
fi
echo "  Found $total deployment(s)"

# Filter out deployments in protected environments up-front (belt + suspenders;
# remove_deployment also enforces this).
protected_count=0
filtered_json='[]'
for (( i=0; i<total; i++ )); do
  env=$(jq -r ".[$i].environment" <<<"$deployments_json")
  if is_protected "$env"; then
    protected_count=$((protected_count + 1))
  else
    filtered_json=$(jq ". + [$(jq ".[$i]" <<<"$deployments_json")]" <<<"$filtered_json")
  fi
done
if (( protected_count > 0 )); then
  echo "  Excluded $protected_count deployment(s) in protected environment(s)"
fi
echo

deployments_json="$filtered_json"
total=$(jq 'length' <<<"$deployments_json")

# ── Helper: delete a deployment ─────────────────────────────────────
remove_deployment() {
  local dep_json="$1"
  local reason="$2"

  local id env sha short_sha
  id=$(jq -r '.id' <<<"$dep_json")
  env=$(jq -r '.environment' <<<"$dep_json")
  sha=$(jq -r '.sha' <<<"$dep_json")
  short_sha="${sha:0:7}"

  if is_protected "$env"; then
    echo "  Protected: skipping deployment ${id} (env=${env}, sha=${short_sha}) — ${reason}"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would delete deployment ${id} (env=${env}, sha=${short_sha}) — ${reason}"
    return
  fi

  # Mark inactive first — GitHub rejects DELETE on an active deployment.
  wait_for_rate_limit_budget
  if ! gh_retry api --method POST "/repos/$REPOSITORY/deployments/$id/statuses" \
      -f state=inactive >/dev/null 2>&1; then
    echo "  Warning: Could not mark deployment ${id} inactive — skipping delete"
    return
  fi

  wait_for_rate_limit_budget
  if gh_retry api --method DELETE "/repos/$REPOSITORY/deployments/$id" >/dev/null 2>&1; then
    echo "  Deleted deployment ${id} (env=${env}, sha=${short_sha}) — ${reason}"
    deleted_count=$((deleted_count + 1))
  else
    echo "  Warning: Could not delete deployment ${id}"
  fi
  sleep "$DELETE_DELAY_SECONDS"
}

deleted_count=0

# ── Step 4: Scenario 1 — released-RC deployments ────────────────────
echo "--- Scenario 1: Released-RC Deployments ---"

remaining_json='[]'
scenario1_deleted=0
for (( i=0; i<total; i++ )); do
  dep=$(jq ".[$i]" <<<"$deployments_json")
  dep_sha=$(jq -r '.sha' <<<"$dep")
  rc_tag="${released_rc_shas[$dep_sha]:-}"
  if [[ -n "$rc_tag" ]]; then
    remove_deployment "$dep" "RC $rc_tag (released)"
    scenario1_deleted=$((scenario1_deleted + 1))
  else
    remaining_json=$(jq ". + [$dep]" <<<"$remaining_json")
  fi
done

if (( scenario1_deleted == 0 )); then
  echo "  No released-RC deployments found"
fi
echo

# ── Step 5: Scenario 2 — superseded per environment ─────────────────
echo "--- Scenario 2: Superseded Per Environment ---"

# Bucket remaining deployments by environment.
readarray -t sorted_envs < <(jq -r '[.[].environment] | unique | .[]' <<<"$remaining_json" | sort)

for env in "${sorted_envs[@]}"; do
  env_deployments=$(jq --arg e "$env" '[.[] | select(.environment == $e)]' <<<"$remaining_json")
  env_count=$(jq 'length' <<<"$env_deployments")
  if (( env_count <= KEEP_COUNT )); then
    continue
  fi

  # Sort newest-first for cap calculation, then reverse candidates so oldest go first.
  # If the run is rate-limited mid-sweep, the boundary (freshest-of-candidates) survives.
  candidates=$(jq --argjson keep "$KEEP_COUNT" '
    sort_by(.created_at) | reverse | .[$keep:] | sort_by(.created_at)
  ' <<<"$env_deployments")
  candidate_count=$(jq 'length' <<<"$candidates")

  echo
  echo "Environment: $env (total=$env_count, keep-cap=$KEEP_COUNT, candidates=$candidate_count, oldest-first)"

  for (( i=0; i<candidate_count; i++ )); do
    dep=$(jq ".[$i]" <<<"$candidates")
    created_at=$(jq -r '.created_at' <<<"$dep")
    id=$(jq -r '.id' <<<"$dep")
    created_epoch=$(date -u -d "$created_at" +%s)
    if (( created_epoch >= cutoff_epoch )); then
      echo "  Retained $id (beyond keep-cap but within retention floor)"
      continue
    fi
    remove_deployment "$dep" "superseded, beyond keep-count=$KEEP_COUNT and past retention"
  done
done

echo
echo "========================================"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  Dry run complete. $deleted_count deployment(s) would be deleted."
else
  echo "  Cleanup complete. $deleted_count deployment(s) deleted."
fi
echo "========================================"
