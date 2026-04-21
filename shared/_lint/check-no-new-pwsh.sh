#!/usr/bin/env bash
# check-no-new-pwsh.sh — fail PRs that introduce new pwsh usage.
#
# Policy (see README.md "Shell choice"):
#   - No new `shell: pwsh` in action.yml/action.yaml files added in this PR.
#   - No new `.ps1` files added anywhere outside shared/_test-* harnesses.
#
# Existing pwsh stays — the rule only checks files ADDED vs the base ref, so
# unrelated edits to pwsh actions are not blocked.

set -euo pipefail

base="${1:-origin/main}"
errors=0

# `git diff --diff-filter=A` lists files added since `base`.
added=$(git diff --name-only --diff-filter=A "$base"...HEAD || true)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  if [[ "$file" == *.ps1 ]]; then
    # Allow new test harnesses under shared/_test-*
    if [[ "$file" != shared/_test-* ]]; then
      echo "::error file=$file::New .ps1 files are not allowed. New scripts must be bash (.sh). See README 'Shell choice' section."
      errors=$((errors + 1))
    fi
    continue
  fi

  base_name=$(basename "$file")
  if [[ "$base_name" == "action.yml" || "$base_name" == "action.yaml" ]]; then
    if grep -q 'shell: *pwsh' "$file"; then
      echo "::error file=$file::New action.yml uses 'shell: pwsh'. New actions must use 'shell: bash'. See README 'Shell choice' section."
      errors=$((errors + 1))
    fi
  fi
done <<< "$added"

if (( errors > 0 )); then
  echo "::error::Shell policy violations: $errors. See README.md 'Shell choice — bash only for new work'."
  exit 1
fi

echo "Shell policy check passed (base=$base)."
