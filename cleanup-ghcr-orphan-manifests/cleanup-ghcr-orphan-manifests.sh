#!/usr/bin/env bash
#
# cleanup-ghcr-orphan-manifests.sh — delete untagged GHCR manifests older than
# RETENTION_DAYS that are NOT referenced by any active tagged manifest list
# or attestation index.
#
# Orphan sources include re-pushed tags (the previous digest is left
# untagged), failed/aborted pushes, and stale provenance/SBOM blobs. Children
# of currently-tagged OCI/Docker indexes (multi-arch images, attestation
# manifests for `provenance: mode=max` / `sbom: true`) are preserved.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../shared/retry.sh
source "$SCRIPT_DIR/../shared/retry.sh"

# jq.exe under Windows Git Bash ends lines with CRLF; strip the \r so local
# runs parse the same values as CI (a stray \r corrupts digests and URLs).
jq() { command jq "$@" | tr -d '\r'; }

: "${RETENTION_DAYS:=30}"
: "${CONTAINER_PACKAGES:=}"
: "${DELETE_DELAY_SECONDS:=10}"
: "${RATE_LIMIT_THRESHOLD:=50}"
: "${DRY_RUN:=false}"
: "${REPOSITORY:=${GITHUB_REPOSITORY:-}}"

if [[ -z "$REPOSITORY" ]]; then
  echo "::error::REPOSITORY env var is required"
  exit 1
fi

if [[ -z "$CONTAINER_PACKAGES" ]]; then
  echo "::error::container-packages input is required"
  exit 1
fi

owner="${REPOSITORY%%/*}"
cutoff_epoch=$(date -u -d "$RETENTION_DAYS days ago" +%s)

echo "========================================"
echo "  Orphan Manifest Cleanup"
echo "========================================"
echo
echo "Repository:           $REPOSITORY"
echo "Retention Days:       $RETENTION_DAYS"
echo "Container Packages:   $CONTAINER_PACKAGES"
echo "Delete Delay:         ${DELETE_DELAY_SECONDS}s"
if (( RATE_LIMIT_THRESHOLD > 0 )); then
  echo "Rate-Limit Threshold: $RATE_LIMIT_THRESHOLD"
else
  echo "Rate-Limit Threshold: (disabled)"
fi
echo "Dry Run:              $DRY_RUN"
echo

wait_for_rate_limit_budget() {
  (( RATE_LIMIT_THRESHOLD <= 0 )) && return
  local rl rl_err remaining reset now wait_secs
  # Best-effort: a failed probe must not abort the cleanup, but it must say why
  # the budget check was skipped instead of failing silently.
  rl_err=$(mktemp)
  if ! rl=$(gh api rate_limit --jq '.resources.core | "\(.remaining) \(.reset)"' 2>"$rl_err"); then
    echo "::warning::Rate-limit probe failed; continuing without the budget check: $(cat "$rl_err")"
    rm -f "$rl_err"
    return
  fi
  rm -f "$rl_err"
  read -r remaining reset <<<"$rl"
  if ! [[ "$remaining" =~ ^[0-9]+$ && "$reset" =~ ^[0-9]+$ ]]; then
    echo "::warning::Rate-limit probe returned unexpected output '$rl'; continuing without the budget check"
    return
  fi
  (( remaining >= RATE_LIMIT_THRESHOLD )) && return
  now=$(date +%s)
  wait_secs=$((reset - now + 5))
  (( wait_secs <= 0 )) && return
  echo "::warning::Rate limit low ($remaining remaining, threshold $RATE_LIMIT_THRESHOLD). Waiting ${wait_secs}s for reset..."
  sleep "$wait_secs"
}

wait_for_rate_limit_budget

# Parse container-packages into an array.
package_list=()
IFS=',' read -r -a pkgs_raw <<<"$CONTAINER_PACKAGES"
for p in "${pkgs_raw[@]}"; do
  trimmed=$(echo "$p" | xargs)
  [[ -n "$trimmed" ]] && package_list+=("$trimmed")
done

if (( ${#package_list[@]} == 0 )); then
  echo "::error::container-packages input parsed to empty list"
  exit 1
fi

deleted_count=0
dry_run_count=0

for package in "${package_list[@]}"; do
  pkg_path="$owner/$package"
  echo
  echo "Package $package:"

  # Fetch versions for this package.
  versions_err=$(mktemp)
  if ! versions_raw=$(retry_run gh api "/orgs/$owner/packages/container/${package//\//%2F}/versions" --paginate 2>"$versions_err"); then
    # Fail hard: a skipped package would silently leave its orphans behind.
    cat "$versions_err" >&2
    if grep -q 'HTTP 404' "$versions_err"; then
      echo "::error::Package $package not found in GHCR ($owner) — check container-packages"
    else
      echo "::error::Could not list versions for GHCR package $package ($owner) — check the token has read:packages and the package grants this repo access"
    fi
    rm -f "$versions_err"
    exit 1
  fi
  cat "$versions_err" >&2
  rm -f "$versions_err"
  versions=$(echo "$versions_raw" | jq -s 'add // []')
  vcount=$(jq 'length' <<<"$versions")
  echo "  Versions: $vcount"
  [[ "$vcount" == "0" ]] && continue

  # Exchange the GH token for a registry pull token (works for both public
  # and private packages on GHCR).
  # Fail hard on any failure: without a token no manifest can be inspected.
  if ! token_json=$(retry_run curl -fsS -u "$owner:$GH_TOKEN" \
    "https://ghcr.io/token?scope=repository:$pkg_path:pull&service=ghcr.io"); then
    echo "::error::Could not obtain a GHCR registry token for $pkg_path — check the token has read:packages and the package grants this repo access"
    exit 1
  fi
  reg_token=$(jq -r '.token // empty' <<<"$token_json")
  if [[ -z "$reg_token" ]]; then
    echo "::error::GHCR token exchange for $pkg_path returned no token (malformed response)"
    exit 1
  fi

  # For each tagged version, fetch its manifest. If the manifest is an
  # OCI/Docker index (manifest list, used for multi-arch and for SBOM /
  # provenance attestations), collect the children's digests — these are
  # *referenced* by an active tag and MUST NOT be deleted.
  #
  # Fail hard if any manifest can't be fetched or parsed: treating a failed
  # fetch as "no children" would leave live children unprotected, and the
  # delete loop below would remove them, breaking the tagged image.
  declare -A protected_digests=()
  tagged_count=0
  while IFS= read -r tagged_digest; do
    [[ -z "$tagged_digest" ]] && continue
    tagged_count=$((tagged_count + 1))
    if ! manifest_json=$(retry_run curl -fsS \
      -H "Authorization: Bearer $reg_token" \
      -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
      "https://ghcr.io/v2/$pkg_path/manifests/$tagged_digest"); then
      echo "::error::Could not fetch manifest $pkg_path@$tagged_digest — aborting so its child manifests aren't deleted as orphans"
      exit 1
    fi
    if ! children=$(jq -r '.manifests[]?.digest // empty' <<<"$manifest_json"); then
      echo "::error::Manifest $pkg_path@$tagged_digest isn't valid JSON — aborting so its child manifests aren't deleted as orphans"
      exit 1
    fi
    while IFS= read -r child; do
      [[ -n "$child" ]] && protected_digests["$child"]=1
    done <<<"$children"
  done < <(jq -r '.[] | select((.metadata.container.tags | length) > 0) | .name' <<<"$versions")

  echo "  Tagged versions inspected: $tagged_count, protected child digests: ${#protected_digests[@]}"

  candidates=0
  while IFS=$'\t' read -r untagged_id untagged_digest untagged_created; do
    [[ -z "$untagged_id" ]] && continue
    if [[ -n "${protected_digests[$untagged_digest]:-}" ]]; then
      continue
    fi
    created_epoch=$(date -u -d "$untagged_created" +%s 2>/dev/null || echo "")
    if [[ -z "$created_epoch" ]] || (( created_epoch >= cutoff_epoch )); then
      continue
    fi
    candidates=$((candidates + 1))

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [DRY RUN] Would delete orphan manifest: $untagged_digest (id $untagged_id, created $untagged_created)"
      dry_run_count=$((dry_run_count + 1))
      continue
    fi

    wait_for_rate_limit_budget
    if retry_run gh api --method DELETE "/orgs/$owner/packages/container/${package//\//%2F}/versions/$untagged_id" >/dev/null; then
      echo "  Deleted orphan manifest: $untagged_digest (id $untagged_id)"
      deleted_count=$((deleted_count + 1))
    else
      echo "  Warning: Could not delete orphan manifest version $untagged_id"
    fi
    sleep "$DELETE_DELAY_SECONDS"
  done < <(jq -r '.[] | select((.metadata.container.tags | length) == 0) | "\(.id)\t\(.name)\t\(.created_at)"' <<<"$versions")

  if (( candidates == 0 )); then
    echo "  No orphan manifests past retention."
  fi

  unset protected_digests
  declare -A protected_digests=()
done

echo
echo "========================================"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  Dry run complete. $dry_run_count orphan manifest(s) would be deleted."
else
  echo "  Cleanup complete. $deleted_count orphan manifest(s) deleted."
fi
echo "========================================"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "deleted-count=$deleted_count"
    echo "dry-run-count=$dry_run_count"
  } >>"$GITHUB_OUTPUT"
fi

exit 0
