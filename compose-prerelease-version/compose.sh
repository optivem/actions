#!/usr/bin/env bash
set -euo pipefail

if [[ ! "$BASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Invalid version format: $BASE_VERSION. Expected: X.Y.Z (e.g., 1.0.0)"
  exit 1
fi

if [[ -n "$PREFIX" ]]; then
  version="${PREFIX}-v${BASE_VERSION}-${SUFFIX}.${BUILD_NUMBER}"
else
  version="v${BASE_VERSION}-${SUFFIX}.${BUILD_NUMBER}"
fi

echo "Composed prerelease version: $version"
echo "version=$version" >> "$GITHUB_OUTPUT"
