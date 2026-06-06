#!/usr/bin/env bash
set -euo pipefail
VER="$(gh optivem --version 2>&1 || true)"
# REF empty = the latest release was installed; REF set = built from source at that ref.
if [[ -z "$REF" ]]; then
  SRC="latest release"
else
  SRC="source @ $REF"
fi
echo "Installed gh-optivem ($SRC): $VER"
echo "- Installed gh-optivem (**$SRC**): \`$VER\`" >> "$GITHUB_STEP_SUMMARY"
