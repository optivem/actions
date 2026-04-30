#!/usr/bin/env bash
set -euo pipefail

if [ -z "$SHA" ]; then
  echo "::error::Input 'commit-sha' is required and was empty"
  exit 1
fi

if [ -z "$BASE_BRANCH" ]; then
  echo "::error::Input 'base-branch' is required and was empty"
  exit 1
fi

git fetch origin "$BASE_BRANCH" --quiet

# git merge-base --is-ancestor exits 0 (ancestor), 1 (not ancestor), or
# 128/other (error: bad SHA, missing ref, etc.). Distinguish all three —
# collapsing exit 128 into "not ancestor" would be a swallow.
set +e
git merge-base --is-ancestor "$SHA" "origin/$BASE_BRANCH"
rc=$?
set -e

case "$rc" in
  0)
    echo "on-branch=true" >> "$GITHUB_OUTPUT"
    echo "SHA $SHA is on origin/$BASE_BRANCH" >> "$GITHUB_STEP_SUMMARY"
    ;;
  1)
    echo "on-branch=false" >> "$GITHUB_OUTPUT"
    echo "SHA $SHA is NOT on origin/$BASE_BRANCH" >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    echo "::error::git merge-base --is-ancestor exited with $rc probing $SHA against origin/$BASE_BRANCH. Indeterminate (likely a bad SHA or missing ref) — exiting 1 rather than coercing to on-branch=false."
    exit 1
    ;;
esac
