#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/retry.sh"

# GHCR secondary rate limits ask the caller to "wait a few minutes", but the
# shared ladder (4 attempts / 5+15+45 = 65s) is too short to outlast one — a
# throttled pull exhausts its retries and fails the stage while the limit is
# still in force. Override the wrapper's own knobs for the deploy path only:
# `retry_run` re-reads `_RETRY_ATTEMPTS`/`_RETRY_DELAYS` into the core knobs on
# every call, which is the documented per-wrapper override seam (see
# retry-core.sh, "Wrappers can override ... per call from their own knobs").
# Scoped here so the gh / sonar / git retry timings stay untouched.
_RETRY_ATTEMPTS=5
_RETRY_DELAYS=(15 45 90 180)   # 330s ≈ 5.5 min total across 5 attempts

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

echo "📥 Pulling images (with retry)..."
if [[ -n "$COMPOSE_FILE" ]]; then
  retry_run docker compose -f "$COMPOSE_FILE" pull
else
  retry_run docker compose pull
fi
echo ""

echo "🐳 Running docker compose up (with retry)..."

# Retried, not just `pull`ed: `compose pull` skips build-only services, so a
# compose file with a `build:` section resolves its base images and any
# `# syntax=` directive here instead — a registry blip at that point would
# otherwise fail the stage outright. Safe to re-run: `compose up` is
# declarative and converges.
if [[ -n "$COMPOSE_FILE" ]]; then
  echo "📄 Using compose file: $COMPOSE_FILE"
  retry_run docker compose -f "$COMPOSE_FILE" up -d
else
  retry_run docker compose up -d
fi
