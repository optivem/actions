#!/usr/bin/env bash
# sync-shared.sh — vendor the unified retry helper from
# optivem/actions/shared/ into the downstream repos that still need a
# self-contained runtime copy.
#
# Run from anywhere; the script resolves paths relative to itself. Re-run
# after editing the canonical retry.sh or retry-core.sh, then commit each
# downstream repo via /commit.
#
#   bash optivem/actions/scripts/sync-shared.sh
#
# Vendored helpers: retry-core.sh, retry.sh
# Targets:
#   - ../gh-optivem/.github/scripts/  (internal tool, not student-facing)
#
# Shop no longer vendors retry helpers — it consumes them via
# `uses: optivem/actions/retry@main` instead. See
# plans/20260515-0723-shop-zero-retry-scripts.md.
#
# Each vendored copy gets a banner pinning it to the canonical file's current
# git blob SHA, immediately after the shebang line:
#
#   #!/usr/bin/env bash
#   # GENERATED — DO NOT EDIT.
#   # Source: optivem/actions/shared/<helper>.sh @ <blob-sha>
#   # Sync via: bash optivem/actions/scripts/sync-shared.sh
#   <original body>
#
# Idempotent: running it twice with no canonical changes produces the same
# vendored content. The banner SHA is the git blob hash of the canonical
# file, so drift between canonical and vendored is detectable by visual
# inspection (the banner SHA won't match `git hash-object shared/<helper>.sh`
# in actions).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIONS_ROOT="$(cd "$HERE/.." && pwd)"
ACADEMY_ROOT="$(cd "$ACTIONS_ROOT/.." && pwd)"
SHARED_DIR="$ACTIONS_ROOT/shared"

HELPERS=(retry-core retry)
TARGETS=(
    "$ACADEMY_ROOT/gh-optivem/.github/scripts"
)

for target in "${TARGETS[@]}"; do
    if [[ ! -d "$target" ]]; then
        echo "skip: $target does not exist" >&2
        continue
    fi
    for helper in "${HELPERS[@]}"; do
        src="$SHARED_DIR/$helper.sh"
        dst="$target/$helper.sh"
        if [[ ! -f "$src" ]]; then
            echo "skip: $src missing" >&2
            continue
        fi
        sha=$(git hash-object "$src" 2>/dev/null || echo "unknown")
        rel="optivem/actions/shared/$helper.sh"
        {
            head -n1 "$src"
            cat <<BANNER
# GENERATED — DO NOT EDIT.
# Source: $rel @ $sha
# Sync via: bash optivem/actions/scripts/sync-shared.sh
BANNER
            tail -n +2 "$src"
        } >"$dst"
        chmod +x "$dst"
        echo "vendored: $dst @ $sha"
    done
done
