#!/usr/bin/env bash
set -euo pipefail
SRC="${RUNNER_TEMP}/gh-optivem"
# Binary must be named exactly `gh-optivem` for `gh extension install <dir>`.
( cd "$SRC" && go build -o gh-optivem . )
# Remove any prior install (released or local) so the local build wins.
gh extension remove optivem 2>/dev/null || true
gh extension install "$SRC"
