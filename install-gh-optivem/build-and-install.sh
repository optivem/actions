#!/usr/bin/env bash
set -euo pipefail
SRC="${RUNNER_TEMP}/gh-optivem"
# Binary must be named exactly `gh-optivem` (and the dir must be named
# `gh-optivem`) for a local install to register as the `optivem` extension.
( cd "$SRC" && go build -o gh-optivem . )
# Remove any prior install (released or local) so the local build wins.
if ! rm_err=$(gh extension remove optivem 2>&1); then
  case "$rm_err" in
    *"not installed"*|*"no such extension"*|*"no extension found"*|*"not found"*) : ;;  # expected — nothing to remove
    *) echo "WARNING: gh extension remove failed (continuing): $rm_err" >&2 ;;
  esac
fi
# gh only accepts `.` for a local extension directory — passing an absolute
# path is treated as an OWNER/REPO and rejected. So install from inside $SRC.
cd "$SRC"
gh extension install .
