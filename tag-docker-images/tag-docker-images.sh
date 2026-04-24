#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

# Env vars are always set by the action.yml (possibly to empty string).
IMAGE_URLS="${IMAGE_URLS:-}"
TARGET_TAG="${TARGET_TAG:-}"
IMAGE_TAGS="${IMAGE_TAGS:-}"

# Determine mode. Mutually exclusive:
#   Broadcast: IMAGE_URLS + TARGET_TAG set, IMAGE_TAGS empty.
#   Map:       IMAGE_TAGS set, IMAGE_URLS + TARGET_TAG empty.
broadcast_mode=false
map_mode=false

if [[ -n "$IMAGE_URLS" || -n "$TARGET_TAG" ]]; then
  if [[ -z "$IMAGE_URLS" || -z "$TARGET_TAG" ]]; then
    echo "::error::Broadcast mode requires both 'image-urls' and 'tag'. Got image-urls='${IMAGE_URLS}', tag='${TARGET_TAG}'."
    exit 1
  fi
  broadcast_mode=true
fi

if [[ -n "$IMAGE_TAGS" ]]; then
  map_mode=true
fi

if $broadcast_mode && $map_mode; then
  echo "::error::Mutually exclusive inputs: provide either (image-urls + tag) OR image-tags, not both."
  exit 1
fi

if ! $broadcast_mode && ! $map_mode; then
  echo "::error::No inputs provided. Use (image-urls + tag) for broadcast mode or image-tags for map mode."
  exit 1
fi

# --- Shared retag helper ---------------------------------------------------

new_image_urls=()
failed_images=()
total_count=0

# retag_image <source_url> <target_tag>
# Appends to new_image_urls on success, failed_images on failure.
retag_image() {
  local source_image_url="$1"
  local target_tag="$2"

  echo "📋 Processing: $source_image_url"

  if [[ -z "$source_image_url" ]]; then
    echo "  ⚠️  Skipping empty image URL"
    return
  fi

  if [[ "$target_tag" =~ [\<\>:\"\|\?\*\\] ]]; then
    echo "::error::Tag contains invalid characters: $target_tag"
    exit 1
  fi

  if [[ "$source_image_url" != *[:@]* ]]; then
    echo "  ⚠️  Invalid image URL format: $source_image_url"
    echo "  ℹ️  Expected format: registry/image:tag or registry/image@digest"
    new_image_urls+=("$source_image_url")
    failed_images+=("$source_image_url")
    return
  fi

  local base_image_name="${source_image_url%%[:@]*}"
  local ref="${source_image_url#*[:@]}"
  local new_image_url="${base_image_name}:${target_tag}"

  echo "  🔗 Base image: $base_image_name"
  echo "  🏷️  Current reference: $ref"
  echo "  ✨ New image: $new_image_url"

  # Server-side manifest retag — no image data crosses the runner, multi-arch
  # manifest lists are preserved, and no local docker daemon round trip is
  # needed.
  if ! docker buildx imagetools create --tag "$new_image_url" "$source_image_url"; then
    echo "  ❌ Failed to retag image: $source_image_url -> $new_image_url"
    failed_images+=("$source_image_url")
    return
  fi

  new_image_urls+=("$new_image_url")
  echo "  ✅ Successfully retagged: $source_image_url -> $new_image_url"
}

# --- Mode dispatch ---------------------------------------------------------

if $broadcast_mode; then
  echo "🏷️  Mode: broadcast (single tag to all images)"
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

  total_count=${#source_images[@]}
  echo "🔍 Found $total_count images to retag"

  for source_image_url in "${source_images[@]}"; do
    retag_image "$source_image_url" "$TARGET_TAG"
  done
else
  echo "🏷️  Mode: map (per-image tags)"

  if ! echo "$IMAGE_TAGS" | jq -e 'type == "array"' >/dev/null; then
    echo "::error::image-tags must be a JSON array of {key, tag} objects (key = source image URL)"
    exit 1
  fi

  mapfile -t map_entries < <(jq -c '.[]' <<<"$IMAGE_TAGS")

  if [[ ${#map_entries[@]} -eq 0 ]]; then
    echo "::error::No entries found in the provided image-tags JSON array"
    exit 1
  fi

  total_count=${#map_entries[@]}
  echo "🔍 Found $total_count entries to retag"

  for entry in "${map_entries[@]}"; do
    url=$(jq -r '.key // empty' <<<"$entry")
    tag=$(jq -r '.tag // empty' <<<"$entry")

    if [[ -z "$url" || -z "$tag" ]]; then
      echo "::error::Each image-tags entry must have non-empty 'key' (source image URL) and 'tag' fields. Got: $entry"
      exit 1
    fi

    retag_image "$url" "$tag"
  done
fi

# --- Output + summary ------------------------------------------------------

if [[ ${#new_image_urls[@]} -eq 0 ]]; then
  echo "::error::No images were successfully tagged. All $total_count images failed."
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

if [[ ${#failed_images[@]} -eq 0 ]]; then
  echo "✅ Successfully tagged all $total_count Docker images"
else
  echo "⚠️  Partially completed: $success_count/$total_count images tagged successfully"
fi

echo "📤 Output parameter set: tagged-image-urls"
