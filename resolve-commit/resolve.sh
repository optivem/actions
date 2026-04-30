#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

if [ -z "$REF" ]; then
  REF="main"
fi

remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")

# Shallow-fetch just the target ref into a throwaway repo. Works for branches,
# tags, and SHAs (GitHub has uploadpack.allowReachableSHA1InWant enabled).
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

git init --quiet
if ! git fetch --quiet --depth=1 "$remote_url" "$REF"; then
  echo "::error::Failed to resolve $REPO ref '$REF' — ref not found or fetch failed"
  exit 1
fi

SHA=$(git rev-parse FETCH_HEAD)
TIMESTAMP=$(git log -1 --format=%cI FETCH_HEAD)

if [ -z "$SHA" ] || [ ${#SHA} -ne 40 ]; then
  echo "::error::Resolved SHA for $REPO ref '$REF' is invalid: '$SHA'"
  exit 1
fi

echo "sha=$SHA" >> "$GITHUB_OUTPUT"
echo "timestamp=$TIMESTAMP" >> "$GITHUB_OUTPUT"
echo "Resolved $REPO ref '$REF' to SHA: $SHA" >> "$GITHUB_STEP_SUMMARY"
echo "Committer timestamp: $TIMESTAMP" >> "$GITHUB_STEP_SUMMARY"
