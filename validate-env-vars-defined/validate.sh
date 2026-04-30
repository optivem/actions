#!/usr/bin/env bash
set -euo pipefail

missing=()

while IFS= read -r name; do
  name=$(echo "$name" | xargs)
  [ -z "$name" ] && continue
  value=$(printenv "$name" 2>/dev/null || true)
  if [ -z "$value" ]; then
    missing+=("$name")
  fi
done <<< "$VALIDATE_NAMES"

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error::Missing required config: ${missing[*]}"
  exit 1
fi

echo "All required config values are defined."
