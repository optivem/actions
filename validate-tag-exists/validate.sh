#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

echo "Checking if tag '$TAG' exists on $REPO..."

remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")

if git ls-remote --tags "$remote_url" "refs/tags/$TAG" 2>/dev/null | grep -q "refs/tags/$TAG"; then
  echo "✅ Tag '$TAG' found in $REPO"
  exit 0
fi

echo "::error::Tag '$TAG' does not exist in repository '$REPO'. Make sure the tag is correct and was created by a previous stage."
exit 1
