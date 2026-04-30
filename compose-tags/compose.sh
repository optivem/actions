#!/usr/bin/env bash
set -euo pipefail

if ! echo "$VERSIONS" | jq -e 'type == "array"' >/dev/null; then
  echo "::error::versions must be a JSON array of {key, version} objects"
  exit 1
fi

if [[ "$TEMPLATE" != *'{version}'* ]]; then
  echo "::error::template must contain the {version} placeholder. Got: $TEMPLATE"
  exit 1
fi

output='[]'
while IFS= read -r entry; do
  key=$(jq -r '.key // empty' <<<"$entry")
  version=$(jq -r '.version // empty' <<<"$entry")

  if [ -z "$key" ] || [ -z "$version" ]; then
    echo "::error::Each entry must have non-empty 'key' and 'version' fields. Got: $entry"
    exit 1
  fi

  tag="${TEMPLATE//\{version\}/$version}"

  output=$(jq -c --arg key "$key" --arg tag "$tag" '. + [{key: $key, tag: $tag}]' <<<"$output")
done < <(jq -c '.[]' <<<"$VERSIONS")

echo "tags=$output" >> "$GITHUB_OUTPUT"
