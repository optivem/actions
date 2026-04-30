#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

if [ -z "$PREFIX" ]; then
  echo "::error::tag-prefix is required."
  exit 1
fi

remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")

if [ -n "$SUFFIX" ]; then
  pattern="refs/tags/${PREFIX}*${SUFFIX}"
  label="${PREFIX}*${SUFFIX}"
else
  pattern="refs/tags/${PREFIX}*"
  label="${PREFIX}*"
fi

TAG=$(git ls-remote --tags "$remote_url" "$pattern" 2>/dev/null \
  | awk '{print $2}' \
  | sed 's#refs/tags/##' \
  | grep -v '\^{}$' \
  | sort -V \
  | tail -n 1)

if [ -z "$TAG" ]; then
  echo "::error::No ${label} git tag found in $REPO — create a ${label} tag first, or pass an explicit tag elsewhere."
  exit 1
fi

if [ -n "$SUFFIX" ]; then
  BASE_TAG="${TAG%$SUFFIX}"
else
  BASE_TAG="$TAG"
fi

echo "Resolved latest ${label} git tag in $REPO: $TAG"
echo "Using latest ${label} git tag from $REPO: $TAG" >> "$GITHUB_STEP_SUMMARY"
echo "tag=$TAG" >> "$GITHUB_OUTPUT"
echo "base-tag=$BASE_TAG" >> "$GITHUB_OUTPUT"
