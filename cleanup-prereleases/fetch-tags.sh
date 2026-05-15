#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$GITHUB_ACTION_PATH/../shared/retry.sh"

retry_run git fetch --tags --force
