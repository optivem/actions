#!/usr/bin/env bash
set -euo pipefail
echo "🔧 Formatting artifact list..."

formatted="$(printf '%s\n' "$ARTIFACTS" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | sed '/^$/d' \
  | sed 's/^/• /')"

if [[ -n "$formatted" ]]; then
  echo "📋 Formatted output:"
  echo "$formatted"
else
  echo "ℹ️ No artifacts provided; returning empty output"
fi

{
  echo "formatted<<EOF"
  echo "$formatted"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
echo "✅ Output written to GITHUB_OUTPUT"
