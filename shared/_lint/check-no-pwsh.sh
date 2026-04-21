#!/usr/bin/env bash
# check-no-pwsh.sh — fail PRs that contain any pwsh usage.
#
# Policy (see README.md "Shell choice"):
#   - No `shell: pwsh` in any action.yml/action.yaml.
#   - No `.ps1` files anywhere outside `shared/_test-*` harnesses.
#
# The repo has fully converged on bash — any new or remaining pwsh is
# considered a regression and must be ported.

set -euo pipefail

errors=0

mapfile -t ps1_files < <(
  git ls-files -- '*.ps1' \
    | grep -Ev '^(shared/_test-|\.tmp/|\.claude/|\.plans/)' \
    || true
)

for file in "${ps1_files[@]}"; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue
  echo "::error file=$file::.ps1 files are not allowed. Scripts must be bash (.sh). See README 'Shell choice' section."
  errors=$((errors + 1))
done

mapfile -t yaml_files < <(
  git ls-files -- '**/action.yml' '**/action.yaml' \
    | grep -Ev '^(\.tmp/|\.claude/|\.plans/)' \
    || true
)

for file in "${yaml_files[@]}"; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    echo "::error file=${file},line=${lineno}::'shell: pwsh' is not allowed. Use 'shell: bash'. See README 'Shell choice' section."
    errors=$((errors + 1))
  done < <(grep -nE '^[[:space:]]*shell:[[:space:]]*pwsh\b' "$file" || true)
done

if (( errors > 0 )); then
  echo "::error::Shell policy violations: $errors. See README.md 'Shell choice — bash only'."
  exit 1
fi

echo "Shell policy check passed: no pwsh/.ps1 in production code."
