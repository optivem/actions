#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../shared/gh-retry.sh
source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

ref_regex="^${REF_PREFIX}[0-9]+\\.[0-9]+\\.[0-9]+-rc\\.[0-9]+$"

page=1
while [[ "$page" -le 10 ]]; do
  mapfile -t entries < <(gh_retry api "repos/${REPOSITORY}/deployments?environment=${ENVIRONMENT}&per_page=100&page=${page}" \
    --jq '.[] | "\(.id)|\(.ref)"')
  [[ ${#entries[@]} -eq 0 ]] && break
  for entry in "${entries[@]}"; do
    id="${entry%%|*}"
    ref="${entry##*|}"
    [[ "$ref" =~ $ref_regex ]] || continue
    if [[ -n "$EXCLUDE_REF_PREFIX" && "$ref" == "$EXCLUDE_REF_PREFIX"* ]]; then
      continue
    fi
    # auto_inactive flips earlier successful deployments to `inactive`; check status history, not latest.
    has_success=$(gh_retry api "repos/${REPOSITORY}/deployments/${id}/statuses?per_page=100" --jq '[.[] | select(.state == "success")] | length')
    if [[ "${has_success:-0}" -gt 0 ]]; then
      echo "ref=${ref}" >> "$GITHUB_OUTPUT"
      echo "Resolved latest deployment in ${ENVIRONMENT}: ${ref}" >> "$GITHUB_STEP_SUMMARY"
      exit 0
    fi
  done
  page=$((page+1))
done

echo "::error::No successful deployment found in environment ${ENVIRONMENT} matching ${REF_PREFIX}<X.Y.Z>-rc.<N>"
exit 1
