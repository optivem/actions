#!/usr/bin/env bash
set -euo pipefail

if [[ -z "$LATEST" ]]; then
  echo "::error::latest is empty"
  exit 1
fi

echo "Latest: $LATEST"

if [[ -z "$SINCE" ]]; then
  echo "Since is empty — reporting newer=true (fail-open)."
  echo "newer=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Since:  $SINCE"

# ISO 8601 lexicographic comparison is correct when both timestamps are in UTC
# with the same format (both include 'Z'). GitHub API returns UTC Z-suffixed;
# typical latest timestamps (docker push times, git commit times) are likewise
# UTC Z-suffixed.
if [[ "$LATEST" > "$SINCE" ]]; then
  echo "Latest is newer than since — newer=true"
  newer=true
else
  echo "Latest is not newer than since — newer=false"
  newer=false
fi

echo "newer=$newer" >> "$GITHUB_OUTPUT"
