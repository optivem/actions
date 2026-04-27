#!/usr/bin/env bash
#
# cleanup-orphan-manifests.sh — delete untagged GHCR manifests older than
# RETENTION_DAYS that are NOT referenced by any active tagged manifest list
# or attestation index.
#
# Orphan sources include re-pushed tags (the previous digest is left
# untagged), failed/aborted pushes, and stale provenance/SBOM blobs. Children
# of currently-tagged OCI/Docker indexes (multi-arch images, attestation
# manifests for `provenance: mode=max` / `sbom: true`) are preserved.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../shared/gh-retry.sh
source "$SCRIPT_DIR/../shared/gh-retry.sh"

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
  if ! versions_raw=$(gh_retry api "/orgs/$owner/packages/container/$package/versions" --paginate 2>/dev/null); then
    echo "  Warning: Could not list versions for package $package; skipping"
    continue
  fi
  versions=$(echo "$versions_raw" | jq -s 'add // []')
  vcount=$(jq 'length' <<<"$versions")
  echo "  Versions: $vcount"
  [[ "$vcount" == "0" ]] && continue

  # Exchange the GH token for a registry pull token (works for both public
  # and private packages on GHCR).
  reg_token=$(curl -fsS -u "$owner:$GH_TOKEN" \
    "https://ghcr.io/token?scope=repository:$pkg_path:pull&service=ghcr.io" 2>/dev/null \
    | jq -r '.token // empty')
  if [[ -z "$reg_token" ]]; then
    echo "  Warning: could not obtain registry token for $pkg_path; skipping orphan cleanup"
    continue
  fi

  # For each tagged version, fetch its manifest. If the manifest is an
  # OCI/Docker index (manifest list, used for multi-arch and for SBOM /
  # provenance attestations), collect the children's digests — these are
  # *referenced* by an active tag and MUST NOT be deleted.
  declare -A protected_digests=()
  tagged_count=0
  while IFS= read -r tagged_digest; do
    [[ -z "$tagged_digest" ]] && continue
    tagged_count=$((tagged_count + 1))
    while IFS= read -r child; do
      [[ -n "$child" ]] && protected_digests["$child"]=1
    done < <(curl -fsS \
      -H "Authorization: Bearer $reg_token" \
      -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
      "https://ghcr.io/v2/$pkg_path/manifests/$tagged_digest" 2>/dev/null \
      | jq -r '.manifests[]?.digest // empty' 2>/dev/null)
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
    if gh_retry api --method DELETE "/orgs/$owner/packages/container/$package/versions/$untagged_id" >/dev/null 2>&1; then
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
