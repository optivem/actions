#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VERSION_FILE:-}" ]; then
  echo "::error::Required input 'file' was not provided to read-base-version. Pass file: <path/to/VERSION> explicitly — the action no longer defaults to root VERSION."
  exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
  echo "::error::VERSION file not found at '$VERSION_FILE'. Make sure to include the VERSION file in your repository."
  exit 1
fi
base_version=$(head -n 1 "$VERSION_FILE" | tr -d '[:space:]')
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
