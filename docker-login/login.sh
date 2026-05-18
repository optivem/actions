#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../shared/retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/retry.sh"

: "${USERNAME:?USERNAME is required}"
: "${PASSWORD:?PASSWORD is required}"
REGISTRY="${REGISTRY:-}"

# Wrap the login in a function so the password is re-piped on every retry
# attempt. Piping into `retry_run` directly only feeds stdin to the *first*
# attempt; subsequent attempts get empty stdin and `docker login` falls back
# to interactive mode ("Cannot perform an interactive login from a non TTY
# device") — masking the real transient failure.
do_login() {
  if [[ -n "$REGISTRY" ]]; then
    printf '%s' "$PASSWORD" | docker login "$REGISTRY" --username "$USERNAME" --password-stdin
  else
    printf '%s' "$PASSWORD" | docker login --username "$USERNAME" --password-stdin
  fi
}

retry_run do_login
