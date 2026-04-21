#!/usr/bin/env bash
# check-no-raw-gh.sh — fail PRs that call `gh` without the retry wrapper.
#
# Policy (see README.md "Calling `gh` — use the retry wrapper"):
#   Every `gh <verb>` invocation in production code must go through
#   `gh_retry` (shared/gh-retry.sh) so transient 5xx/network errors are
#   retried transparently. The only exceptions are purely local probes:
#     - `gh auth status`
#     - `gh api rate_limit` (read-only, used by caller-side rate-limit checks)
#
# Scope: action.yml / action.yaml / *.sh / *.ps1 under the repo root,
# excluding shared/, .github/, .tmp/, .plans/, .claude/. Matches are
# filtered to ignore bash comments and YAML `description:`/`name:` prose.

set -euo pipefail

errors=0

# Find candidate files (tracked + untracked, excluding ignored).
mapfile -t files < <(
  git ls-files -- \
    '*.sh' '*.ps1' '**/action.yml' '**/action.yaml' \
    | grep -Ev '^(shared/|\.github/|\.tmp/|\.plans/|\.claude/)' \
    || true
)

for file in "${files[@]}"; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue

  # Match `gh <verb>` where verb is a real subcommand that hits the API.
  # Exit 1 from grep = no matches; normal when file is clean.
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    content="${hit#*:}"

    # Skip bash comment lines (leading `#`).
    if [[ "$content" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    # Skip YAML scalar fields that routinely mention `gh` in prose.
    if [[ "$content" =~ ^[[:space:]]*(description|name|-[[:space:]]+description|-[[:space:]]+name):[[:space:]] ]]; then
      continue
    fi

    # Whitelist: read-only local probes that never hit the retry surface.
    if [[ "$content" =~ gh[[:space:]]+auth[[:space:]]+status ]]; then
      continue
    fi
    if [[ "$content" =~ gh[[:space:]]+api[[:space:]]+rate_limit ]]; then
      continue
    fi

    echo "::error file=${file},line=${lineno}::Raw 'gh' call — must use 'gh_retry' (source shared/gh-retry.sh). Whitelist is 'gh auth status' and 'gh api rate_limit'."
    errors=$((errors + 1))
  done < <(grep -nE '\bgh[[:space:]]+(api|release|workflow|run|repo|pr|issue)\b' "$file" || true)
done

if (( errors > 0 )); then
  echo "::error::Raw gh usage violations: $errors. Wrap with gh_retry — see shared/gh-retry.sh."
  exit 1
fi

echo "gh-usage lint passed: all gh calls in scanned files use gh_retry (or the read-only whitelist)."
