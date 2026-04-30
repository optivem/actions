#!/usr/bin/env bash
# check-shell-scripts.sh — bash -n parse + shellcheck on every *.sh in production code.
#
# Scope: all *.sh tracked by git, excluding plans/, .tmp/, .claude/.
# Includes shared/ — repo-wide bash hygiene applies to shared scripts too.

set -euo pipefail

errors=0

mapfile -t files < <(
  git ls-files -- '*.sh' \
    | grep -Ev '^(\.tmp/|plans/|\.claude/)' \
    || true
)

for file in "${files[@]}"; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue

  if ! bash -n "$file"; then
    echo "::error file=${file}::bash -n parse failed"
    errors=$((errors + 1))
  fi
done

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "::error::shellcheck not installed on runner"
  exit 1
fi

# `--external-sources` lets `# shellcheck source=...` directives cross file boundaries.
if ! shellcheck --external-sources --severity=warning "${files[@]}"; then
  errors=$((errors + 1))
fi

if (( errors > 0 )); then
  echo "::error::Shell-script lint failed."
  exit 1
fi

echo "Shell-script lint passed: ${#files[@]} files."
