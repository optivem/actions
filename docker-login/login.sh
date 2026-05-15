#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/docker-retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/docker-retry.sh"

: "${USERNAME:?USERNAME is required}"
: "${PASSWORD:?PASSWORD is required}"
REGISTRY="${REGISTRY:-}"

if [[ -n "$REGISTRY" ]]; then
  printf '%s' "$PASSWORD" | docker_retry login "$REGISTRY" --username "$USERNAME" --password-stdin
else
  printf '%s' "$PASSWORD" | docker_retry login --username "$USERNAME" --password-stdin
fi
