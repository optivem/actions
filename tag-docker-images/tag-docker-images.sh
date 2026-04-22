#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_URLS:?IMAGE_URLS is required (JSON array of source image URLs)}"
: "${TARGET_TAG:?TARGET_TAG is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

if [[ "$TARGET_TAG" =~ [\<\>:\"\|\?\*\\] ]]; then
  echo "::error::TargetTag contains invalid characters: $TARGET_TAG"
  exit 1
fi

echo "🏷️  Retagging Docker images via buildx imagetools (server-side manifest create)..."
echo "🎯 Target tag: $TARGET_TAG"

if ! source_images_json="$(jq -c 'if type == "array" then . else [.] end' <<<"$IMAGE_URLS")"; then
  echo "::error::Failed to parse image-urls as JSON"
  exit 1
fi

mapfile -t source_images < <(jq -r '.[]' <<<"$source_images_json")

if [[ ${#source_images[@]} -eq 0 ]]; then
  echo "::error::No images found in the provided image-urls JSON array"
  exit 1
fi

echo "🔍 Found ${#source_images[@]} images to retag"

new_image_urls=()
failed_images=()

for source_image_url in "${source_images[@]}"; do
  echo "📋 Processing: $source_image_url"

  if [[ -z "$source_image_url" ]]; then
    echo "  ⚠️  Skipping empty image URL"
    continue
  fi

  if [[ "$source_image_url" == *[:@]* ]]; then
    base_image_name="${source_image_url%%[:@]*}"
    ref="${source_image_url#*[:@]}"
    new_image_url="${base_image_name}:${TARGET_TAG}"

    echo "  🔗 Base image: $base_image_name"
    echo "  🏷️  Current reference: $ref"
    echo "  ✨ New image: $new_image_url"

    # Server-side manifest retag — no image data crosses the runner, multi-arch manifest
    # lists are preserved, and no local docker daemon round trip is needed.
    if ! docker buildx imagetools create --tag "$new_image_url" "$source_image_url"; then
      echo "  ❌ Failed to retag image: $source_image_url -> $new_image_url"
      failed_images+=("$source_image_url")
      continue
    fi

    new_image_urls+=("$new_image_url")
    echo "  ✅ Successfully retagged: $source_image_url -> $new_image_url"
  else
    echo "  ⚠️  Invalid image URL format: $source_image_url"
    echo "  ℹ️  Expected format: registry/image:tag or registry/image@digest"
    new_image_urls+=("$source_image_url")
    failed_images+=("$source_image_url")
  fi
done

if [[ ${#new_image_urls[@]} -eq 0 ]]; then
  echo "::error::No images were successfully tagged. All ${#source_images[@]} images failed."
  exit 1
fi

if [[ ${#failed_images[@]} -gt 0 ]]; then
  echo "⚠️  Warning: ${#failed_images[@]} images failed to process:"
  for failed in "${failed_images[@]}"; do
    echo "  - $failed"
  done
fi

new_image_urls_json="$(printf '%s\n' "${new_image_urls[@]}" | jq -R . | jq -sc .)"

echo "📦 New image URLs: $new_image_urls_json"
echo "tagged-image-urls=$new_image_urls_json" >> "$GITHUB_OUTPUT"

success_count=${#new_image_urls[@]}
total_count=${#source_images[@]}

if [[ ${#failed_images[@]} -eq 0 ]]; then
  echo "✅ Successfully tagged all $total_count Docker images for production"
else
  echo "⚠️  Partially completed: $success_count/$total_count images tagged successfully"
fi

echo "📤 Output parameter set: tagged-image-urls"
