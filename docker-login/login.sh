#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/retry.sh"

: "${USERNAME:?USERNAME is required}"
: "${PASSWORD:?PASSWORD is required}"
REGISTRY="${REGISTRY:-}"

if [[ -n "$REGISTRY" ]]; then
  printf '%s' "$PASSWORD" | retry_run docker login "$REGISTRY" --username "$USERNAME" --password-stdin
else
  printf '%s' "$PASSWORD" | retry_run docker login --username "$USERNAME" --password-stdin
fi
