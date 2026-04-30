#!/usr/bin/env bash
set -euo pipefail

release_title="${TITLE_PREFIX}${RELEASE_VERSION}${TITLE_SUFFIX}"
short_sha="${COMMIT_SHA:0:7}"
timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

notes_file=$(mktemp)
{
  echo "# $release_title"
  echo
  echo "**Release Version:** $RELEASE_VERSION  "
  if [[ -n "$PRERELEASE_VERSION" ]]; then
    echo "**Promoted From:** $PRERELEASE_VERSION  "
  fi
  echo "**Workflow:** [$RUN_ID]($SERVER_URL/$REPOSITORY/actions/runs/$RUN_ID)  "
  echo "**Commit:** [$short_sha]($SERVER_URL/$REPOSITORY/commit/$COMMIT_SHA)  "
  echo "**Actor:** $ACTOR  "
  echo
} > "$notes_file"

if [[ -n "$ARTIFACT_URLS" && "$ARTIFACT_URLS" != "[]" ]]; then
  if artifact_count=$(jq 'length' <<<"$ARTIFACT_URLS" 2>/dev/null); then
    if (( artifact_count > 0 )); then
      {
        echo "## 📦 Artifacts"
        echo
        jq -r '.[] | "- \(.)"' <<<"$ARTIFACT_URLS"
        echo
      } >> "$notes_file"
    fi
  else
    echo "⚠️ Could not parse artifact URLs; skipping artifacts section" >&2
  fi
fi

{
  echo "---"
  echo "*Created: $timestamp*"
} >> "$notes_file"

echo "title=$release_title" >> "$GITHUB_OUTPUT"
echo "notes-file=$notes_file" >> "$GITHUB_OUTPUT"

echo "📝 Generated release title: $release_title"
echo "📄 Notes file: $notes_file"
