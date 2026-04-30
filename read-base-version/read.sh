#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "$VERSION_FILE" ]; then
  echo "::error::VERSION file not found at '$VERSION_FILE'. Make sure to include the VERSION file in your repository."
  exit 1
fi
base_version=$(head -n 1 "$VERSION_FILE" | tr -d '[:space:]')
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
