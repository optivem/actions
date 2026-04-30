#!/usr/bin/env bash
set -euo pipefail

# Requires the caller to have checked out with fetch-depth: 0 (or equivalent)
# so tag history is available. A defensive tag-fetch covers the common case
# where tags were pushed after checkout.
git fetch --tags --force origin >/dev/null 2>&1 || true

# Walk tag-patterns in priority order, take the most recent match from
# the first pattern that matches at least one tag.
BASELINE_TAG=""
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  match=$(git tag --list "$pattern" --sort=-version:refname | head -n 1)
  if [[ -n "$match" ]]; then
    BASELINE_TAG="$match"
    echo "Matched pattern '$pattern' → baseline tag: $BASELINE_TAG"
    break
  fi
  echo "Pattern '$pattern' matched no tags, trying next"
done <<< "$TAG_PATTERNS"

if [[ -z "$BASELINE_TAG" ]]; then
  echo "No tag matched any of the provided patterns — reporting changed=true (fail-open)."
  {
    echo "changed=true"
    echo "baseline-tag="
    echo "baseline-sha="
    echo "changed-files<<EOF"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
  exit 0
fi

BASELINE_SHA=$(git rev-list -n 1 "$BASELINE_TAG")
echo "Baseline: $BASELINE_TAG ($BASELINE_SHA)"
echo "HEAD: ${GITHUB_SHA:-$(git rev-parse HEAD)}"

# Build pathspec args
path_args=()
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  path_args+=("$p")
done <<< "$PATHS"

if [[ ${#path_args[@]} -eq 0 ]]; then
  echo "::error::No paths provided"
  exit 1
fi

CHANGED_FILES=$(git diff --name-only "$BASELINE_SHA" HEAD -- "${path_args[@]}")

{
  echo "baseline-tag=$BASELINE_TAG"
  echo "baseline-sha=$BASELINE_SHA"
} >> "$GITHUB_OUTPUT"

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes in specified paths since $BASELINE_TAG."
  {
    echo "changed=false"
    echo "changed-files<<EOF"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
else
  echo "Changes detected:"
  echo "$CHANGED_FILES"
  {
    echo "changed=true"
    echo "changed-files<<EOF"
    echo "$CHANGED_FILES"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
fi
