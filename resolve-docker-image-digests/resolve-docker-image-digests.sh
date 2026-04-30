#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

BASE_IMAGE_URLS="${BASE_IMAGE_URLS:-}"
TAG="${TAG:-latest}"

echo "Starting batch Docker image digest resolution..."
echo ""

if [[ -z "$BASE_IMAGE_URLS" ]]; then
  echo "::error::base-image-urls must be provided"
  exit 1
fi

tag="$TAG"
echo "Composing image URLs from base-image-urls with tag: $tag"

base_trimmed="$(printf '%s' "$BASE_IMAGE_URLS" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
base_list=()
if [[ "${base_trimmed:0:1}" == "[" && "${base_trimmed: -1}" == "]" ]]; then
  if ! parsed="$(jq -r '.[]' <<<"$base_trimmed" 2>/dev/null)"; then
    echo "::error::Invalid JSON format in base-image-urls input"
    exit 1
  fi
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    base_list+=("$line")
  done <<<"$parsed"
else
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    base_list+=("$line")
  done <<<"$BASE_IMAGE_URLS"
fi

composed=()
for base in "${base_list[@]}"; do
  composed+=("${base}:${tag}")
done
IMAGE_URLS="$(printf '%s\n' "${composed[@]}")"

echo "ImageUrls: $IMAGE_URLS"
echo ""

trimmed="$(printf '%s' "$IMAGE_URLS" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
echo "Trimmed input: '$trimmed'"

image_list=()

if [[ "${trimmed:0:1}" == "[" && "${trimmed: -1}" == "]" ]]; then
  echo "Detected JSON array format"
  if ! parsed="$(jq -r '.[]' <<<"$trimmed" 2>/dev/null)"; then
    echo "::error::Invalid JSON format in image-urls input"
    exit 1
  fi
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    image_list+=("$line")
  done <<<"$parsed"
else
  echo "Detected newline-separated format"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    image_list+=("$line")
  done <<<"$IMAGE_URLS"
fi

if [[ ${#image_list[@]} -eq 0 ]]; then
  echo "::error::No valid image URLs provided. Please provide at least one image URL."
  exit 1
fi

echo "Image URLs:"
for url in "${image_list[@]}"; do
  echo "  - $url"
done

echo "Processing ${#image_list[@]} image(s)..."

results=()
inspect_objects=()
created_timestamps=()

for image_url in "${image_list[@]}"; do
  echo ""
  echo "Processing: $image_url"

  if [[ -z "$image_url" ]]; then
    echo "::error::Empty or invalid image URL provided"
    exit 1
  fi

  echo "Resolving image: $image_url"
  echo "Pulling image to get digest..."
  if ! docker pull "$image_url"; then
    echo "::error::Failed to pull Docker image: $image_url"
    exit 1
  fi

  echo "Resolving digest..."
  if ! inspect_json="$(docker inspect "$image_url")"; then
    echo "::error::Failed to inspect Docker image: $image_url"
    exit 1
  fi

  repo_digest="$(jq -r '.[0].RepoDigests[0] // empty' <<<"$inspect_json")"
  if [[ -z "$repo_digest" ]]; then
    echo "::error::No digest found for image: $image_url. The image may not be from a registry that supports digests."
    exit 1
  fi

  digest="${repo_digest#*@}"
  if [[ "$digest" == "$repo_digest" || -z "$digest" ]]; then
    echo "::error::Could not parse digest from: $repo_digest"
    exit 1
  fi

  if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    echo "Warning: Digest format may be unexpected: $digest"
  fi

  echo "Image digest resolved: $digest"

  if [[ "$image_url" == *@* ]]; then
    digest_url="${image_url%@*}@${digest}"
  elif [[ "$image_url" == *:* ]]; then
    digest_url="${image_url%:*}@${digest}"
  else
    digest_url="${image_url}@${digest}"
  fi

  if ! created_ts="$(docker inspect "$image_url" --format='{{.Created}}')"; then
    echo "Warning: Could not get timestamp for $image_url, using inspect data"
    created_ts="$(jq -r '.[0].Created // ""' <<<"$inspect_json")"
  fi

  results+=("$digest_url")
  inspect_objects+=("$(jq -c '.[0]' <<<"$inspect_json")")
  created_timestamps+=("$created_ts")
done

echo ""
echo "Summary:"
echo "All ${#results[@]} image(s) processed successfully!"

digests_json="$(printf '%s\n' "${results[@]}" | jq -R . | jq -sc .)"
echo "digests=$digests_json" >> "$GITHUB_OUTPUT"

inspect_json_out="$(printf '%s\n' "${inspect_objects[@]}" | jq -sc .)"
echo "inspect-data=$inspect_json_out" >> "$GITHUB_OUTPUT"

timestamps_json="$(printf '%s\n' "${created_timestamps[@]}" | jq -R . | jq -sc .)"
echo "created-timestamps=$timestamps_json" >> "$GITHUB_OUTPUT"

latest_ts="$(printf '%s\n' "${created_timestamps[@]}" | sort | tail -n1)"
echo "latest-updated-at=$latest_ts" >> "$GITHUB_OUTPUT"

echo "JSON results, inspect data, created timestamps, and latest timestamp written to GitHub output"

echo ""
echo "FULL OUTPUT:"
echo "Digest URLs:"
jq . <<<"$digests_json"

echo ""
echo "Inspect Data:"
jq . <<<"$inspect_json_out"

echo ""
echo "Created Timestamps:"
jq . <<<"$timestamps_json"

echo ""
echo "Latest Image Timestamp: $latest_ts"

echo ""
echo "Batch digest resolution completed successfully!"
