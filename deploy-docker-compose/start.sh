#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting system version $VERSION for $ENVIRONMENT..."
echo ""

if [[ -n "$IMAGE_URLS" ]]; then
  echo "📦 Images:"
  echo "$IMAGE_URLS" | jq -r '.[]' | while IFS= read -r image_url; do
    if [[ -n "$image_url" ]]; then
      echo "   🐳 $image_url"
    fi
  done
  echo ""
fi

echo "🐳 Running docker compose up..."

if [[ -n "$COMPOSE_FILE" ]]; then
  echo "📄 Using compose file: $COMPOSE_FILE"
  docker compose -f "$COMPOSE_FILE" up -d
else
  docker compose up -d
fi
