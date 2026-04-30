#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"
# shellcheck source=../shared/clear-persisted-credentials.sh
source "$GITHUB_ACTION_PATH/../shared/clear-persisted-credentials.sh"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

target_sha="${SHA:-$(git rev-parse HEAD)}"

push_target=$(remote_push_target "$TOKEN" "$GIT_HOST" "$REPO")
if [ -n "$TOKEN" ]; then
  clear_persisted_credentials "$GIT_HOST"
fi

existing=$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1)
if [ -n "$existing" ]; then
  if [ "$existing" = "$target_sha" ]; then
    echo "Tag $TAG already exists on remote at $target_sha — no-op"
    echo "Tag $TAG already existed at $target_sha (no-op)" >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  echo "::error::Tag $TAG already exists on remote at $existing, but caller requested $target_sha"
  exit 1
fi

if [ -n "$SHA" ]; then
  git tag "$TAG" "$SHA"
else
  git tag "$TAG"
fi

if git push "$push_target" "$TAG"; then
  echo "Created and pushed tag $TAG at $target_sha" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

remote_sha=$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1)
if [ -n "$remote_sha" ] && [ "$remote_sha" = "$target_sha" ]; then
  echo "Tag $TAG created by concurrent run at same commit — tolerating"
  echo "Tag $TAG created by concurrent run at $target_sha" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

echo "::error::Failed to push tag $TAG (remote: $remote_sha, local: $target_sha)"
exit 1
