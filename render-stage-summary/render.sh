#!/usr/bin/env bash
set -euo pipefail

case "$STAGE_RESULT" in
  success|failure|cancelled|skipped) ;;
  *)
    echo "::error::Invalid stage-result '$STAGE_RESULT'. Must be one of: success, failure, cancelled, skipped."
    exit 1
    ;;
esac

write_header() {
  echo "## $1 $STAGE_NAME $2"
  echo ""
}

write_content() {
  local content="$1" fallback="$2"
  if [[ -n "$content" ]]; then
    printf '%s\n' "$content"
  elif [[ -n "$fallback" ]]; then
    echo "$fallback"
  fi
}

{
  echo "# $STAGE_NAME Summary"
  echo ""

  case "$STAGE_RESULT" in
    success)
      write_header "✅" "Succeeded"
      ;;
    failure)
      write_header "❌" "Failed"
      ;;
    cancelled)
      write_header "🛑" "Cancelled"
      ;;
    skipped)
      write_header "⏭️" "Skipped"
      ;;
  esac

  if [[ -n "$STAGE_CONTENT" ]]; then
    printf '%s\n\n' "$STAGE_CONTENT"
  fi

  case "$STAGE_RESULT" in
    success)
      write_content "$STAGE_SUCCESS_CONTENT" "Stage completed successfully."
      ;;
    failure)
      echo "The stage process encountered an error. Check the job logs for details."
      ;;
    cancelled)
      echo "⏹️ **Stage process was cancelled**"
      ;;
    skipped)
      write_content "$STAGE_SKIPPED_CONTENT" "Stage was skipped."
      ;;
  esac
} >> "$GITHUB_STEP_SUMMARY"
