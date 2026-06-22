#!/usr/bin/env bash
set -euo pipefail
SRC="${RUNNER_TEMP}/gh-optivem"
# Binary must be named exactly `gh-optivem` for `gh extension install <dir>`.
( cd "$SRC" && go build -o gh-optivem . )
# Remove any prior install (released or local) so the local build wins.
if ! rm_err=$(gh extension remove optivem 2>&1); then
  case "$rm_err" in
    *"not installed"*|*"no such extension"*|*"not found"*) : ;;  # expected — nothing to remove
    *) echo "WARNING: gh extension remove failed (continuing): $rm_err" >&2 ;;
  esac
fi
gh extension install "$SRC"
