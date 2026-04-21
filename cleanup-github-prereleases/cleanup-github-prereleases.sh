#!/usr/bin/env bash
#
# cleanup-github-prereleases.sh — delete prerelease git tags, GitHub releases, and
# Docker image tags that are no longer needed.
#
# Three scenarios:
#   1. Released versions (final tag vX.Y.Z exists):
#        immediately delete prerelease GitHub releases and git tags;
#        delete prerelease Docker image tags after retention period.
#   2. Superseded prereleases (no final release yet):
#        per pipeline-prefix, keep the newest RC; older RCs past retention
#        (plus their status tags and Docker tags) are deleted.
#   3. Orphaned prerelease GitHub releases (no git tag):
#        unconditionally delete (drafts or abandoned records).

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

owner="${REPOSITORY%%/*}"
cutoff_epoch=$(date -u -d "$RETENTION_DAYS days ago" +%s)

echo "========================================"
echo "  Prerelease Version Cleanup"
echo "========================================"
echo
echo "Repository:           $REPOSITORY"
echo "Retention Days:       $RETENTION_DAYS"
if [[ -n "$CONTAINER_PACKAGES" ]]; then
  echo "Container Packages:   $CONTAINER_PACKAGES"
else
  echo "Container Packages:   (none - Docker cleanup skipped)"
fi
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

# Check rate-limit headroom before the paginated fetches. Prevents starting
# a long run that would hit the per-delete throttle only after burning quota
# on the enumeration calls.
wait_for_rate_limit_budget

# ── Step 1: Fetch all releases (paginated) ───────────────────────────
echo "Fetching all GitHub releases (single API call)..."

# Pre-index by tag_name: { tag -> { id, created_at, is_prerelease, is_draft } }
# jq builds the dictionary; we look up fields via jq later.
if all_releases_raw=$(gh_retry api "repos/$REPOSITORY/releases" --paginate 2>/dev/null); then
  all_releases=$(echo "$all_releases_raw" | jq -s 'add // [] | map({key: .tag_name, value: {id: .id, created_at: .created_at, is_prerelease: .prerelease, is_draft: .draft}}) | from_entries')
  release_count=$(jq 'length' <<<"$all_releases")
  echo "  Found $release_count releases"
else
  all_releases='{}'
  echo "  No releases found or could not fetch"
fi

# ── Step 2: Fetch all Docker package versions (one batch per package) ─
declare -A docker_versions_json    # package -> JSON array of version records

package_list=()
if [[ -n "$CONTAINER_PACKAGES" ]]; then
  IFS=',' read -r -a pkgs_raw <<<"$CONTAINER_PACKAGES"
  for p in "${pkgs_raw[@]}"; do
    trimmed=$(echo "$p" | xargs)
    [[ -n "$trimmed" ]] && package_list+=("$trimmed")
  done
fi

for package in "${package_list[@]}"; do
  echo "Fetching Docker versions for package: $package..."
  if versions_raw=$(gh_retry api "/orgs/$owner/packages/container/$package/versions" --paginate 2>/dev/null); then
    docker_versions_json[$package]=$(echo "$versions_raw" | jq -s 'add // []')
    vcount=$(jq 'length' <<<"${docker_versions_json[$package]}")
    echo "  Found $vcount versions"
  else
    docker_versions_json[$package]='[]'
    echo "  Warning: Could not list versions for package $package"
  fi
done

echo
echo "API fetching complete. Processing locally from here."
echo

# ── Helpers (no API calls) ───────────────────────────────────────────
get_tag_creation_date_epoch() {
  local tag="$1"
  local iso

  iso=$(jq -r --arg t "$tag" '.[$t].created_at // empty' <<<"$all_releases")
  if [[ -n "$iso" ]]; then
    date -u -d "$iso" +%s
    return 0
  fi

  iso=$(git log -1 --format=%aI "$tag" 2>/dev/null || true)
  if [[ -n "$iso" ]]; then
    date -u -d "$iso" +%s
    return 0
  fi

  echo ""
}

deleted_count=0

remove_git_tag() {
  local tag="$1"

  # Safety net: never delete a final release tag (vX.Y.Z shape, optionally
  # prefixed — e.g. "v1.0.0", "meta-v1.0.0"), even if upstream categorization
  # misclassified it into a prerelease bucket.
  if [[ "$tag" =~ ^([a-z][a-z0-9-]*-)?v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "  Protected: skipping final release git tag $tag"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would delete git tag: $tag"
    return
  fi

  if ! git push origin --delete "refs/tags/$tag" 2>/dev/null; then
    echo "  Warning: Could not delete remote tag $tag (may not exist on remote)"
  fi
  git tag -d "$tag" 2>/dev/null || true

  echo "  Deleted git tag: $tag"
  sleep "$DELETE_DELAY_SECONDS"
}

remove_github_release() {
  local tag="$1"

  # Lookup from pre-fetched data (no API call).
  local exists is_prerelease
  exists=$(jq -r --arg t "$tag" 'has($t)' <<<"$all_releases")
  [[ "$exists" != "true" ]] && return

  is_prerelease=$(jq -r --arg t "$tag" '.[$t].is_prerelease' <<<"$all_releases")
  if [[ "$is_prerelease" != "true" ]]; then
    echo "  Protected: skipping final GitHub release $tag (isPrerelease=false)"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would delete GitHub release: $tag"
    return
  fi

  wait_for_rate_limit_budget
  if gh_retry release delete "$tag" --repo "$REPOSITORY" --yes --cleanup-tag >/dev/null 2>&1; then
    echo "  Deleted GitHub release: $tag"
  else
    echo "  Warning: Could not delete release $tag"
  fi
  sleep "$DELETE_DELAY_SECONDS"
}

remove_docker_image_tag() {
  local package="$1"
  local tag="$2"

  local versions="${docker_versions_json[$package]:-[]}"
  [[ "$versions" == "[]" ]] && return

  # Find the version record containing this tag.
  local match
  match=$(jq --arg t "$tag" 'map(select(.metadata.container.tags | index($t))) | .[0] // empty' <<<"$versions")
  [[ -z "$match" ]] && return

  local tag_count
  tag_count=$(jq '.metadata.container.tags | length' <<<"$match")
  if (( tag_count > 1 )); then
    local tags_joined
    tags_joined=$(jq -r '.metadata.container.tags | join(", ")' <<<"$match")
    local version_id
    version_id=$(jq -r '.id' <<<"$match")
    echo "  Warning: Version $version_id has multiple tags ($tags_joined). Skipping to avoid deleting other tags."
    return
  fi

  local version_id
  version_id=$(jq -r '.id' <<<"$match")

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would delete Docker image tag: $package:$tag"
    return
  fi

  wait_for_rate_limit_budget
  if gh_retry api --method DELETE "/orgs/$owner/packages/container/$package/versions/$version_id" >/dev/null 2>&1; then
    echo "  Deleted Docker image tag: $package:$tag"
  else
    echo "  Warning: Could not delete Docker image version $version_id"
  fi
  sleep "$DELETE_DELAY_SECONDS"
}

get_tag_prefix() {
  local tag="$1"
  if [[ "$tag" =~ ^([a-z][a-z0-9-]*)-v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# ── Step 3: Categorize git tags (local, no API calls) ────────────────
echo "Categorizing tags..."

declare -A final_releases           # "1.0.0" -> "v1.0.0"
declare -A prerelease_tags_map      # "1.0.0" -> space-separated RC tags
declare -A status_tags_map          # "1.0.0" -> space-separated status tags

all_tags_arr=()
while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  all_tags_arr+=("$tag")
done < <(git tag -l)

if (( ${#all_tags_arr[@]} == 0 )); then
  echo "No tags found. Nothing to clean up."
  exit 0
fi

for tag in "${all_tags_arr[@]}"; do
  # Final release (prefixed or not: "v1.0.0", "meta-v1.0.0")
  if [[ "$tag" =~ ^([a-z][a-z0-9-]*-)?v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    final_releases[${BASH_REMATCH[2]}]="$tag"
  # Status tag: <prefix?>v<X.Y.Z>-<word>.<N>-<more>
  elif [[ "$tag" =~ ^([a-z][a-z0-9-]*-)?v([0-9]+\.[0-9]+\.[0-9]+)-[a-zA-Z0-9_]+\.[0-9]+-.+$ ]]; then
    version="${BASH_REMATCH[2]}"
    existing="${status_tags_map[$version]:-}"
    status_tags_map[$version]="${existing:+$existing }$tag"
  # Plain prerelease: <prefix?>v<X.Y.Z>-<word>.<N>
  elif [[ "$tag" =~ ^([a-z][a-z0-9-]*-)?v([0-9]+\.[0-9]+\.[0-9]+)-[a-zA-Z0-9_]+\.[0-9]+$ ]]; then
    version="${BASH_REMATCH[2]}"
    existing="${prerelease_tags_map[$version]:-}"
    prerelease_tags_map[$version]="${existing:+$existing }$tag"
  fi
done

# ── Scenario 1: Released versions ────────────────────────────────────
echo
echo "--- Released Versions ---"

# Sort versions oldest-first by release-tag creation date.
sorted_released_versions=()
while IFS=$'\t' read -r ts ver; do
  sorted_released_versions+=("$ver")
done < <(
  for version in "${!final_releases[@]}"; do
    ts=$(get_tag_creation_date_epoch "${final_releases[$version]}")
    [[ -z "$ts" ]] && ts=9999999999
    printf '%s\t%s\n' "$ts" "$version"
  done | sort -n
)

for version in "${sorted_released_versions[@]}"; do
  release_tag="${final_releases[$version]}"
  release_epoch=$(get_tag_creation_date_epoch "$release_tag")
  docker_eligible=false
  if [[ -n "$release_epoch" && "$release_epoch" -lt "$cutoff_epoch" ]]; then
    docker_eligible=true
  fi

  rc_tags_str="${prerelease_tags_map[$version]:-}"
  st_tags_str="${status_tags_map[$version]:-}"

  if [[ -z "$rc_tags_str" && -z "$st_tags_str" ]]; then
    continue
  fi

  echo
  echo "Version $version (released as $release_tag)"

  # Delete all prerelease GitHub releases and git tags immediately.
  for tag in $rc_tags_str $st_tags_str; do
    remove_github_release "$tag"
    remove_git_tag "$tag"
    deleted_count=$((deleted_count + 1))
  done

  # Delete Docker image tags only after retention period.
  if (( ${#package_list[@]} > 0 )) && [[ -n "$rc_tags_str" ]]; then
    if [[ "$docker_eligible" == "true" ]]; then
      echo "  Docker retention period passed (released $(date -u -d "@$release_epoch" -Iseconds))"
      for package in "${package_list[@]}"; do
        for tag in $rc_tags_str; do
          remove_docker_image_tag "$package" "$tag"
        done
      done
    else
      echo "  Docker images retained (released epoch $release_epoch, cutoff epoch $cutoff_epoch)"
    fi
  fi
done

# ── Scenario 2: Superseded prereleases (no final release) ───────────
echo
echo "--- Superseded Prereleases ---"

# Sort prerelease versions oldest-first by earliest RC creation date.
sorted_prerelease_versions=()
while IFS=$'\t' read -r ts ver; do
  sorted_prerelease_versions+=("$ver")
done < <(
  for version in "${!prerelease_tags_map[@]}"; do
    min_ts=9999999999
    for rc in ${prerelease_tags_map[$version]}; do
      ts=$(get_tag_creation_date_epoch "$rc")
      if [[ -n "$ts" ]] && (( ts < min_ts )); then
        min_ts=$ts
      fi
    done
    printf '%s\t%s\n' "$min_ts" "$version"
  done | sort -n
)

for version in "${sorted_prerelease_versions[@]}"; do
  # Skip versions already handled in Scenario 1.
  if [[ -n "${final_releases[$version]:-}" ]]; then
    continue
  fi

  rc_tags_str="${prerelease_tags_map[$version]}"
  rc_count=$(echo "$rc_tags_str" | wc -w)
  if (( rc_count <= 1 )); then
    continue
  fi

  # Group RCs by pipeline prefix.
  declare -A rcs_by_prefix=()
  for rc in $rc_tags_str; do
    prefix=$(get_tag_prefix "$rc")
    existing="${rcs_by_prefix[$prefix]:-}"
    rcs_by_prefix[$prefix]="${existing:+$existing }$rc"
  done

  for prefix in "${!rcs_by_prefix[@]}"; do
    prefix_rcs_str="${rcs_by_prefix[$prefix]}"
    prefix_rc_count=$(echo "$prefix_rcs_str" | wc -w)
    if (( prefix_rc_count <= 1 )); then
      continue
    fi

    # Sort RC tags by RC number ascending (oldest first for cleanup).
    sorted_rcs_str=$(printf '%s\n' $prefix_rcs_str | awk '{
      if (match($0, /\.[0-9]+$/)) {
        n = substr($0, RSTART + 1)
      } else {
        n = 0
      }
      printf "%d\t%s\n", n, $0
    }' | sort -n | cut -f2)

    latest_rc=$(echo "$sorted_rcs_str" | tail -n 1)
    older_rcs=$(echo "$sorted_rcs_str" | head -n -1)

    prefix_label="no prefix"
    [[ -n "$prefix" ]] && prefix_label="prefix '$prefix'"

    echo
    echo "Version $version, $prefix_label (unreleased, latest: $latest_rc)"

    while IFS= read -r rc_tag; do
      [[ -z "$rc_tag" ]] && continue
      tag_epoch=$(get_tag_creation_date_epoch "$rc_tag")
      if [[ -z "$tag_epoch" ]] || (( tag_epoch >= cutoff_epoch )); then
        echo "  Retained $rc_tag (within retention window)"
        continue
      fi

      echo "  Cleaning up $rc_tag (created epoch $tag_epoch)"

      remove_github_release "$rc_tag"
      remove_git_tag "$rc_tag"
      deleted_count=$((deleted_count + 1))

      # Delete associated status tags (those that start with "<rc>-").
      st_tags_str="${status_tags_map[$version]:-}"
      for st_tag in $st_tags_str; do
        if [[ "$st_tag" == "$rc_tag-"* ]]; then
          remove_github_release "$st_tag"
          remove_git_tag "$st_tag"
          deleted_count=$((deleted_count + 1))
        fi
      done

      # Delete Docker image tags for this superseded RC.
      if (( ${#package_list[@]} > 0 )); then
        for package in "${package_list[@]}"; do
          remove_docker_image_tag "$package" "$rc_tag"
        done
      fi
    done <<<"$older_rcs"
  done

  unset rcs_by_prefix
  declare -A rcs_by_prefix=()
done

# ── Scenario 3: Orphaned prerelease GitHub releases (no git tag) ─────
echo
echo "--- Orphaned Prerelease Releases ---"

# Build set of known git tags for fast lookup.
declare -A git_tag_set=()
for tag in "${all_tags_arr[@]}"; do
  git_tag_set[$tag]=1
done

release_tag_names=()
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  release_tag_names+=("$t")
done < <(jq -r 'keys[]' <<<"$all_releases")

for tag_name in "${release_tag_names[@]}"; do
  is_prerelease=$(jq -r --arg t "$tag_name" '.[$t].is_prerelease' <<<"$all_releases")
  [[ "$is_prerelease" != "true" ]] && continue
  [[ -n "${git_tag_set[$tag_name]:-}" ]] && continue

  rel_id=$(jq -r --arg t "$tag_name" '.[$t].id' <<<"$all_releases")
  rel_created=$(jq -r --arg t "$tag_name" '.[$t].created_at' <<<"$all_releases")
  is_draft=$(jq -r --arg t "$tag_name" '.[$t].is_draft' <<<"$all_releases")
  kind="orphaned"
  [[ "$is_draft" == "true" ]] && kind="draft"

  echo "  Cleaning up $kind release $tag_name (created $rel_created)"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would delete release: $tag_name (id $rel_id)"
    continue
  fi

  # Delete by release ID (drafts have no tag, so by-tag delete is unreliable).
  wait_for_rate_limit_budget
  if gh_retry api --method DELETE "repos/$REPOSITORY/releases/$rel_id" >/dev/null 2>&1; then
    echo "  Deleted release: $tag_name"
    deleted_count=$((deleted_count + 1))
  else
    echo "  Warning: Could not delete release $tag_name (id $rel_id)"
  fi
  sleep "$DELETE_DELAY_SECONDS"
done

# ── Summary ──────────────────────────────────────────────────────────
echo
echo "========================================"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  Dry run complete. $deleted_count item(s) would be deleted."
else
  echo "  Cleanup complete. $deleted_count item(s) deleted."
fi
echo "========================================"

exit 0
