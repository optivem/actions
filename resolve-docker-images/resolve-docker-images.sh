#!/usr/bin/env bash
set -euo pipefail

: "${TAG:?TAG is required}"
: "${BASE_IMAGE_URLS:?BASE_IMAGE_URLS is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo "🔍 Validating input parameters..."

if [[ -z "${TAG// }" ]]; then
  echo "::error::Tag parameter cannot be empty"
  exit 1
fi

if [[ -z "${BASE_IMAGE_URLS// }" ]]; then
  echo "::error::base-image-urls cannot be empty"
  exit 1
fi

echo "🔍 Processing base image URLs..."

base_urls=()
trimmed="$(printf '%s' "$BASE_IMAGE_URLS" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ "$trimmed" == \[* && "$trimmed" == *\] ]] && parsed="$(jq -r '.[]' <<<"$trimmed" 2>/dev/null)"; then
  echo "📋 Detected JSON array format"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    base_urls+=("$line")
  done <<<"$parsed"
else
  echo "📋 Using newline-separated format"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    base_urls+=("$line")
  done <<<"$BASE_IMAGE_URLS"
fi

if [[ ${#base_urls[@]} -eq 0 ]]; then
  echo "::error::No valid base image URLs found after processing input"
  echo "📋 Raw input: '$BASE_IMAGE_URLS'"
  exit 1
fi

echo "✅ Input validation passed:"
echo "  📦 Tag: $TAG"
echo "  🐳 Base URLs count: ${#base_urls[@]}"
for url in "${base_urls[@]}"; do
  echo "    - $url"
done

echo "🐳 Constructing Docker URLs for tag $TAG..."
full_urls=()
for base_url in "${base_urls[@]}"; do
  full_urls+=("${base_url}:${TAG}")
done

echo "🏷️  Tag: $TAG"
for url in "${full_urls[@]}"; do
  echo "   🐳 $url"
done

echo "🔍 Verifying Docker images exist..."
for image_url in "${full_urls[@]}"; do
  echo "Checking: $image_url"
  if docker manifest inspect "$image_url" >/dev/null 2>&1; then
    echo "✅ Image exists: $image_url"
  else
    echo "::error::Docker image not found: $image_url"
    exit 1
  fi
done
echo "✅ All Docker images verified successfully"

docker_urls_json="$(printf '%s\n' "${full_urls[@]}" | jq -R . | jq -sc .)"

echo "Setting GitHub Actions outputs..."
echo "🔍 Debug - Raw JSON value: '$docker_urls_json'"
echo "🔍 Debug - JSON length: ${#docker_urls_json}"

echo "image-urls=$docker_urls_json" >> "$GITHUB_OUTPUT"

echo "🔍 Debug - Checking GITHUB_OUTPUT file contents:"
if [[ -f "$GITHUB_OUTPUT" ]]; then
  echo "GITHUB_OUTPUT contents:"
  cat "$GITHUB_OUTPUT"
fi

echo "📋 GitHub Actions Outputs Set:"
echo "  image-urls: $docker_urls_json"

echo "✅ All Docker images found and validated"
