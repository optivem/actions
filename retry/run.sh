#!/usr/bin/env bash
# run.sh — entry point for the optivem/actions/retry@main composite.
# Reads CMD + WD from env (set by action.yml), then dispatches through
# shared/retry.sh.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../shared/retry.sh
source "$HERE/../shared/retry.sh"

cd "${WD:-.}"

# shellcheck disable=SC2086  # word-splitting on CMD is intentional — caller
# passes a full shell command string and expects it parsed as such.
eval "retry_run $CMD"
