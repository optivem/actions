#!/usr/bin/env bash
# check-no-inline-run.sh — fail PRs that keep inline `run: |` blocks in action.yml.
#
# Policy: every `run:` step in a composite action must invoke a script file:
#   run: bash "$GITHUB_ACTION_PATH/<name>.sh"
# This keeps shellcheck and bash -n authoritative on every line of shell
# logic, removes ${{ }} masking noise from shellcheck output, and forces
# inputs through env: (which is the recommended injection-safe pattern).
#
# Scope: every action.yml / action.yaml under the repo root,
# excluding .tmp/, plans/, .claude/.

set -euo pipefail

errors=0

mapfile -t files < <(
  git ls-files -- '**/action.yml' '**/action.yaml' \
    | grep -Ev '^(\.tmp/|plans/|\.claude/)' \
    || true
)

for file in "${files[@]}"; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    echo "::error file=${file},line=${lineno}::Inline 'run: |' block — extract to a script and invoke as 'run: bash \"\$GITHUB_ACTION_PATH/<name>.sh\"'."
    errors=$((errors + 1))
  done < <(grep -nE '^[[:space:]]+run:[[:space:]]*\|' "$file" || true)
done

if (( errors > 0 )); then
  echo "::error::Inline run-block violations: $errors. Extract each block to a .sh file."
  exit 1
fi

echo "No-inline-run lint passed: every run: invokes a script."
