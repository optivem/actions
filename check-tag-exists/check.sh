#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

echo "Checking for tag '$TAG' in $REPO..."

remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")

if ! output=$(git ls-remote --tags "$remote_url" "refs/tags/${TAG}" 2>/dev/null); then
  echo "::error::Failed to query tags from $REPO"
  exit 1
fi

if [ -n "$output" ]; then
  count=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  echo "Found ${count} tag(s) matching '$TAG' in $REPO"
  echo "exists=true" >> "$GITHUB_OUTPUT"
else
  echo "No tag matching '$TAG' found in $REPO"
  echo "exists=false" >> "$GITHUB_OUTPUT"
fi
