#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/git-retry.sh
source "$GITHUB_ACTION_PATH/../shared/git-retry.sh"

git_fetch_retry --tags --force
