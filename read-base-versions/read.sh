#!/usr/bin/env bash
set -euo pipefail

if ! echo "$ENTRIES" | jq -e 'type == "array"' >/dev/null; then
  echo "::error::entries must be a JSON array of {key, file, repo?} objects"
  exit 1
fi

output='[]'
while IFS= read -r entry; do
  key=$(jq -r '.key // empty' <<<"$entry")
  file=$(jq -r '.file // empty' <<<"$entry")
  repo=$(jq -r '.repo // empty' <<<"$entry")

  if [ -z "$key" ] || [ -z "$file" ]; then
    echo "::error::Each entry must have non-empty 'key' and 'file' fields. Got: $entry"
    exit 1
  fi

  if [ -n "$repo" ]; then
    # Cross-repo fetch via API
    if ! api_response=$(gh api "repos/$repo/contents/$file" --jq '.content' 2>&1); then
      echo "::error::Failed to fetch $file from $repo (key: $key): $api_response"
      exit 1
    fi
    version=$(echo "$api_response" | base64 -d | head -n 1 | tr -d '[:space:]')
  else
    # Local read
    if [ ! -f "$file" ]; then
      echo "::error::VERSION file not found: $file (key: $key)"
      exit 1
    fi
    version=$(head -n 1 "$file" | tr -d '[:space:]')
  fi

  if [ -z "$version" ]; then
    echo "::error::VERSION file is empty: $file (key: $key)"
    exit 1
  fi

  output=$(jq -c --arg key "$key" --arg version "$version" '. + [{key: $key, version: $version}]' <<<"$output")
done < <(jq -c '.[]' <<<"$ENTRIES")

echo "versions=$output" >> "$GITHUB_OUTPUT"
