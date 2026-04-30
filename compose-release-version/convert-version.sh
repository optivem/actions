#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PRERELEASE_VERSION:-}" ]]; then
  echo "::error::prerelease-version is required"
  exit 1
fi

echo "Input prerelease version: $PRERELEASE_VERSION"

# Strip any SemVer-§9 prerelease identifier of the shape -<alphabetic-word>.<digits>.
# Matches rc, alpha, beta, preview, dev, nightly, hotfix, etc. — any caller-chosen
# suffix that follows the convention.
release=$(printf '%s' "$PRERELEASE_VERSION" | sed -E 's/-[A-Za-z][A-Za-z0-9]*\.[0-9]+$//')

if [[ -z "$release" ]]; then
  echo "::error::Failed to generate release version from: $PRERELEASE_VERSION"
  exit 1
fi

# Fail-fast if a prerelease identifier is still present after stripping — indicates
# the input didn't match the expected shape.
if [[ "$release" =~ -[A-Za-z][A-Za-z0-9]*\.[0-9]+$ ]]; then
  echo "::error::prerelease-version '$PRERELEASE_VERSION' still contains a prerelease identifier after stripping: '$release'. Expected shape: <base>-<word>.<number>."
  exit 1
fi

if [[ "$PRERELEASE_VERSION" == v* && "$release" != v* ]]; then
  release="v$release"
fi

echo "Generated release version: $release"
echo "version=$release" >> "$GITHUB_OUTPUT"
