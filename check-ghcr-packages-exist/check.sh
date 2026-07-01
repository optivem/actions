#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/ghcr-probe.sh
source "$GITHUB_ACTION_PATH/../shared/ghcr-probe.sh"

any_exist=false
checked=0
results='[]'

while IFS= read -r line; do
  # Trim whitespace and skip blanks.
  line=$(printf '%s' "$line" | tr -d '[:space:]')
  [ -z "$line" ] && continue

  if [[ "$line" != ghcr.io/* ]]; then
    echo "::error::image-urls entries must begin with 'ghcr.io/'. Got: $line"
    exit 1
  fi

  # Parse optional ":tag" suffix. OCI image paths contain no ":", so
  # splitting on the last ":" is unambiguous.
  if [[ "$line" == *:* ]]; then
    image_url=${line%:*}
    effective_tag=${line##*:}
  else
    image_url=$line
    effective_tag=$TAG
  fi

  checked=$((checked + 1))
  path=${image_url#ghcr.io/}
  manifest_url="https://ghcr.io/v2/${path}/manifests/${effective_tag}"

  bearer_out=$(ghcr_bearer_for "$path" "$GH_TOKEN") || true
  bearer=$(sed -n '1p' <<<"$bearer_out")
  bearer_status=$(sed -n '2p' <<<"$bearer_out")
  if [ -z "$bearer" ]; then
    case "$bearer_status" in
      401)
        echo "::error::GHCR token exchange returned HTTP 401 for $path — token is invalid or expired. Rotate the token or re-authenticate."
        ;;
      403)
        echo "::error::GHCR token exchange returned HTTP 403 for $path — token lacks 'read:packages' scope for this package. Grant the scope, or ensure the package owner allows this workflow to read it."
        ;;
      200)
        echo "::error::GHCR token exchange returned HTTP 200 for $path but the response had no token field (malformed response) — investigate GHCR."
        ;;
      *)
        echo "::error::GHCR token exchange returned HTTP $bearer_status for $path after retries — indeterminate failure (network error or unexpected response), treat as failure."
        ;;
    esac
    exit 1
  fi

  code=$(ghcr_probe_manifest "$manifest_url" "$bearer")
  case "$code" in
    200)
      echo "Exists: ${image_url}:${effective_tag}"
      exists=true
      any_exist=true
      ;;
    404)
      echo "Missing: ${image_url}:${effective_tag}"
      exists=false
      ;;
    401)
      echo "::error::Unauthenticated probing ${image_url}:${effective_tag} (HTTP 401). The token used by this workflow is missing or invalid — rotate the token or re-authenticate."
      exit 1
      ;;
    403)
      echo "::error::Permission denied probing ${image_url}:${effective_tag} (HTTP 403). The token is valid but lacks 'read:packages' on this package — grant the scope, or ensure the package owner allows this workflow to read it."
      exit 1
      ;;
    *)
      echo "::error::Unexpected HTTP $code probing ${image_url}:${effective_tag} after retries (treat as indeterminate, not as 'absent')."
      exit 1
      ;;
  esac

  results=$(jq -c --arg image "$image_url" --arg tag "$effective_tag" --argjson exists "$exists" '. + [{image: $image, tag: $tag, exists: $exists}]' <<<"$results")
done <<< "$IMAGE_URLS"

if [ "$checked" = "0" ]; then
  echo "::error::image-urls input was empty after trimming."
  exit 1
fi

if [ "$any_exist" != "true" ]; then
  echo "::notice::No tag found on any of the $checked probed packages — all absent."
fi

{
  echo "exist=$any_exist"
  echo "results=$results"
} >> "$GITHUB_OUTPUT"
