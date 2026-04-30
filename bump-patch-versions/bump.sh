#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

if ! jq -e 'type == "array"' >/dev/null <<<"$VERSION_FILES"; then
  echo "::error::version-files must be a JSON array of {path, value} objects"
  exit 1
fi

probe_git_tag() {
  local tag=$1
  local remote_url
  remote_url=$(remote_query_url "$GH_TOKEN" "github.com" "$REPOSITORY")
  local output
  if ! output=$(git ls-remote --tags "$remote_url" "refs/tags/${tag}" 2>/dev/null); then
    echo "::error::Failed to query tags from ${REPOSITORY}" >&2
    exit 1
  fi
  if [ -n "$output" ]; then
    echo "true"
  else
    echo "false"
  fi
}

bumps='[]'
bumped=false
summary=""

while IFS= read -r entry; do
  path=$(jq -r '.path // empty' <<<"$entry")
  value=$(jq -r '.value // empty' <<<"$entry")
  signal=$(jq -r '.signal // empty' <<<"$entry")

  if [ -z "$path" ] || [ -z "$value" ]; then
    echo "::error::Each entry must have non-empty 'path' and 'value' fields. Got: $entry"
    exit 1
  fi

  # Backward compat: tolerate legacy `signal: git-tag`; reject anything else.
  if [ -n "$signal" ] && [ "$signal" != "git-tag" ]; then
    echo "::error::Legacy 'signal' field for $path must be 'git-tag' (or omitted). Got: '$signal'. The 'ghcr-image' signal has been removed."
    exit 1
  fi

  if [[ ! -f "$path" ]]; then
    echo "::warning::VERSION file not found: $path"
    continue
  fi
  current_version=$(tr -d '[:space:]' < "$path")
  if [[ -z "$current_version" ]]; then
    echo "::warning::VERSION file is empty: $path"
    continue
  fi

  release_signal="${value}${current_version}"
  exists=$(probe_git_tag "$release_signal")

  if [[ "$exists" != "true" ]]; then
    echo "Skipped $path: $current_version (no tag at $release_signal)"
    summary="${summary}${path}: skipped (no tag for $current_version)\n"
    continue
  fi

  major=$(cut -d. -f1 <<<"$current_version")
  minor=$(cut -d. -f2 <<<"$current_version")
  patch=$(cut -d. -f3 <<<"$current_version")
  new_version="${major}.${minor}.$((patch + 1))"

  bumps=$(jq -c --arg p "$path" --arg ov "$current_version" --arg nv "$new_version" --arg rs "$release_signal" \
    '. + [{path: $p, "old-version": $ov, "new-version": $nv, "release-signal": $rs}]' <<<"$bumps")

  echo "Planned bump: $path $current_version -> $new_version (artifact $release_signal)"
  summary="${summary}${path}: ${current_version} -> ${new_version}\n"
  bumped=true
done < <(jq -c '.[]' <<<"$VERSION_FILES")

{
  echo "bumps=$bumps"
  echo "bumped=$bumped"
  echo "summary<<EOF"
  echo -e "$summary"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
