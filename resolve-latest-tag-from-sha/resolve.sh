#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/remote-url.sh
source "$GITHUB_ACTION_PATH/../shared/remote-url.sh"

# TODO(scale): git ls-remote --tags fetches the full tag list and filters client-side.
# For repos with thousands of tags this is slower than a paginated `gh api /repos/.../tags`.
# At this repo's scale (dozens of tags) it is fine. Revisit when tag counts grow.
remote_url=$(remote_query_url "$TOKEN" "$GIT_HOST" "$REPO")

# git ls-remote --tags prints: "<sha>\t<ref>".
# Annotated tags appear twice: once for the tag-object SHA (refs/tags/X) and once
# peeled to the commit it points at (refs/tags/X^{}). Lightweight tags appear once
# with the commit SHA directly. Match on the commit SHA; strip the "refs/tags/"
# prefix and any "^{}" suffix to recover the tag name. Then filter by the caller's
# glob pattern and pick the highest by version sort.
TAG=$(
  git ls-remote --tags "$remote_url" | awk -v sha="$SHA" '
    $1 == sha {
      ref = $2
      sub(/^refs\/tags\//, "", ref)
      sub(/\^\{\}$/, "", ref)
      print ref
    }
  ' | while IFS= read -r t; do
    # shellcheck disable=SC2254  # $PATTERN is intentionally a glob for tag matching
    case "$t" in
      $PATTERN) echo "$t" ;;
    esac
  done | sort -V | tail -1
)

echo "tag=$TAG" >> "$GITHUB_OUTPUT"
if [ -n "$TAG" ]; then
  echo "Resolved $REPO SHA $SHA to tag: $TAG (pattern: $PATTERN)" >> "$GITHUB_STEP_SUMMARY"
else
  echo "No tag matching '$PATTERN' found in $REPO pointing at $SHA" >> "$GITHUB_STEP_SUMMARY"
fi
