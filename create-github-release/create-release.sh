#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"

if [ ! -f "$NOTES_FILE" ]; then
  echo "::error::Release notes file not found: $NOTES_FILE"
  exit 1
fi

# Probe for an existing release (gh also finds drafts). Only "release not found"
# means absent; any other failure (auth, network, 5xx after retries) is fatal.
set +e
probe_output=$(retry_run gh release view "$TAG" --repo "$REPO" --json isDraft 2>&1)
probe_rc=$?
set -e

if [ "$probe_rc" -eq 0 ]; then
  echo "Release $TAG already exists in $REPO — publishing and updating it"
  retry_run gh release edit "$TAG" --repo "$REPO" \
    --draft=false --prerelease="$PRERELEASE" \
    --title "$TITLE" --notes-file "$NOTES_FILE"
  echo "Published existing release $TAG" >> "$GITHUB_STEP_SUMMARY"
elif grep -qi "release not found" <<<"$probe_output"; then
  generate_flag=()
  if [ "$GENERATE_NOTES" = "true" ]; then
    generate_flag=(--generate-notes)
  fi
  retry_run gh release create "$TAG" --repo "$REPO" \
    --prerelease="$PRERELEASE" "${generate_flag[@]}" \
    --title "$TITLE" --notes-file "$NOTES_FILE"
  echo "Created release $TAG" >> "$GITHUB_STEP_SUMMARY"
else
  echo "$probe_output"
  echo "::error::Could not determine whether release $TAG exists in $REPO. Check that the token has contents:read on the repository."
  exit 1
fi
