#!/usr/bin/env bash
set -euo pipefail

if ! echo "$SKIP_CONDITIONS" | jq empty >/dev/null 2>&1; then
  echo "::error::skip-conditions is not valid JSON. Got: $SKIP_CONDITIONS"
  exit 1
fi
if ! echo "$SKIP_CONDITIONS" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "::error::skip-conditions must be a JSON array of {when, reason} entries."
  exit 1
fi

count=$(echo "$SKIP_CONDITIONS" | jq 'length')
for (( i=0; i<count; i++ )); do
  when=$(echo "$SKIP_CONDITIONS" | jq -r ".[$i].when")
  reason=$(echo "$SKIP_CONDITIONS" | jq -r ".[$i].reason")
  if [[ "$when" == "true" ]]; then
    echo "should-run=false" >> "$GITHUB_OUTPUT"
    {
      echo 'skip-reason<<GATE_REASON_EOF'
      printf '%s\n' "$reason"
      echo 'GATE_REASON_EOF'
    } >> "$GITHUB_OUTPUT"
    echo "Gate blocked at condition #$i: $reason"
    exit 0
  fi
done

echo "should-run=true" >> "$GITHUB_OUTPUT"
echo "skip-reason=" >> "$GITHUB_OUTPUT"
echo "Gate passed: no skip conditions matched, run will proceed."
