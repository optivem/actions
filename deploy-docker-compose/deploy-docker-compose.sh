#!/usr/bin/env bash
set -euo pipefail

# Reads:
#   IMAGE_URLS    — JSON array of image URLs (e.g. '["ghcr.io/.../foo@sha256:..."]')
#   SERVICE_NAMES — newline-separated list of compose service names, in the same order as IMAGE_URLS
# Writes:
#   SYSTEM_IMAGE_<UPPER(name)>=<url> entries into $GITHUB_ENV, one per (url, name) pair.
#   Compose files consume these via ${SYSTEM_IMAGE_<NAME>:-...} substitution.

if [[ -z "${IMAGE_URLS:-}" ]]; then
  echo "::error::image-urls input is required (JSON array of image URLs)"
  exit 1
fi

if [[ -z "${SERVICE_NAMES:-}" ]]; then
  echo "::error::service-names input is required (newline-separated list matching image-urls order)"
  exit 1
fi

mapfile -t urls < <(echo "$IMAGE_URLS" | jq -r '.[]')
mapfile -t names < <(echo "$SERVICE_NAMES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true)

url_count=${#urls[@]}
name_count=${#names[@]}

if (( url_count == 0 )); then
  echo "::error::image-urls parsed to 0 entries — input must be a non-empty JSON array"
  echo "::error::received: $IMAGE_URLS"
  exit 1
fi

if (( url_count != name_count )); then
  echo "::error::image-urls count ($url_count) does not match service-names count ($name_count)"
  echo "::error::image-urls: ${urls[*]}"
  echo "::error::service-names: ${names[*]}"
  exit 1
fi

echo "🔗 Exporting compose image env vars:"
for i in "${!urls[@]}"; do
  name="${names[$i]}"
  url="${urls[$i]}"
  var="SYSTEM_IMAGE_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
  echo "   $var=$url"
  echo "$var=$url" >> "$GITHUB_ENV"
done
