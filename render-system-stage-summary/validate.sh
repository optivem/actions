#!/usr/bin/env bash
set -euo pipefail
echo "🔍 Validating inputs..."
if [[ "$STAGE_RESULT" == "success" ]]; then
  if [[ -z "${SUCCESS_VERSION// }" ]]; then
    echo "::error::success-version is required when stage-result is 'success'"
    exit 1
  fi
  echo "✅ Validation passed: success-version is provided for successful stage"
else
  echo "ℹ️ Stage result is '$STAGE_RESULT', skipping success validation"
fi
echo "✅ Input validation completed"
