#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

# Caller must have run actions/checkout with fetch-depth: 0 (or fetched
# tags by another mechanism) — git tag --list and git rev-parse below
# need the local refs.

if [[ -n "$VERSION" ]]; then
  glob="${TAG_PREFIX}${VERSION}-rc.*"
  escaped_version="${VERSION//./\\.}"
  pattern="^${TAG_PREFIX}${escaped_version}-rc\\.[0-9]+$"
else
  glob="${TAG_PREFIX}*-rc.*"
  pattern="^${TAG_PREFIX}[0-9]+\\.[0-9]+\\.[0-9]+-rc\\.[0-9]+$"
fi

mapfile -t rc_tags < <(git tag --list "$glob" \
  | awk -v p="$pattern" '$0 ~ p' \
  | awk -F'-rc[.]' '{print $NF " " $0}' \
  | sort -k1,1 -nr \
  | awk '{print $2}')

for tag in "${rc_tags[@]}"; do
  sha=$(git rev-parse "${tag}^{}" 2>/dev/null || git rev-parse "${tag}")
  statuses=$(gh_retry api "repos/${REPOSITORY}/commits/${sha}/statuses" --paginate)
  approved=$(echo "$statuses" | jq --arg ctx "$STATUS_CONTEXT" '[.[] | select(.context==$ctx and .state=="success")] | length')
  if [[ "${approved:-0}" -gt 0 ]]; then
    echo "tag=${tag}" >> "$GITHUB_OUTPUT"
    echo "Resolved latest rc with passing [${STATUS_CONTEXT}] commit-status: ${tag}" >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
done

if [[ -n "$VERSION" ]]; then
  echo "::error::No rc tag matching ${TAG_PREFIX}${VERSION}-rc.<N> has a successful [${STATUS_CONTEXT}] commit-status"
else
  echo "::error::No rc tag matching ${TAG_PREFIX}<X.Y.Z>-rc.<N> has a successful [${STATUS_CONTEXT}] commit-status"
fi
exit 1
