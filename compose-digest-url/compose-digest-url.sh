#!/usr/bin/env bash
set -euo pipefail

: "${BASE_IMAGE_URL:?BASE_IMAGE_URL is required}"
: "${DIGEST:?DIGEST is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

base="$(printf '%s' "$BASE_IMAGE_URL" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
digest="$(printf '%s' "$DIGEST" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ -z "$base" ]]; then
  echo "::error::base-image-url cannot be empty"
  exit 1
fi

if [[ "$digest" != sha256:* ]]; then
  echo "::error::digest must be in 'sha256:...' form, got: '$digest'"
  exit 1
fi

digest_url="${base}@${digest}"

echo "🐳 Digest URL: $digest_url"
echo "digest-url=$digest_url" >> "$GITHUB_OUTPUT"
