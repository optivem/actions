#!/usr/bin/env bash
set -euo pipefail

COUNT=$(echo "$ENDPOINTS" | jq 'length')

if [[ "$COUNT" -eq 0 ]]; then
  echo "⚠️ No endpoints provided, skipping health checks"
  exit 0
fi

echo "⏳ Waiting for $COUNT endpoint(s) to be ready (timeout: ${TIMEOUT_SECONDS}s)..."
echo ""

DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

# Cap exponential growth so a long-running pipeline doesn't wait 8+ minutes between probes.
MAX_BACKOFF=$((WAIT_SECONDS * 16))
FAILED=0
TIMED_OUT=0

for i in $(seq 0 $((COUNT - 1))); do
  NAME=$(echo "$ENDPOINTS" | jq -r ".[$i].name")
  URL=$(echo "$ENDPOINTS" | jq -r ".[$i].url")

  echo "⏳ Waiting for $NAME at $URL..."

  attempt=1

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    now=$(date +%s)
    if [ "$now" -ge "$DEADLINE" ]; then
      echo "❌ Timed out after ${TIMEOUT_SECONDS}s waiting for $NAME (hard timeout reached)"
      TIMED_OUT=1
      FAILED=1
      break
    fi

    if curl -f "$URL" > /dev/null 2>&1; then
      echo "✅ $NAME is ready!"
      break
    fi
    backoff=$((WAIT_SECONDS * (2 ** (attempt - 1))))
    if [ "$backoff" -gt "$MAX_BACKOFF" ]; then backoff=$MAX_BACKOFF; fi
    jitter=$((RANDOM % 3))
    sleep_secs=$((backoff + jitter))

    # Clamp sleep to the remaining deadline so we exit promptly on timeout.
    remaining=$(( DEADLINE - $(date +%s) ))
    if [ "$remaining" -le 0 ]; then
      echo "❌ Timed out after ${TIMEOUT_SECONDS}s waiting for $NAME (hard timeout reached)"
      TIMED_OUT=1
      FAILED=1
      break
    fi
    if [ "$sleep_secs" -gt "$remaining" ]; then sleep_secs=$remaining; fi

    echo "🔄 Attempt $attempt/$MAX_ATTEMPTS: $NAME not ready yet, waiting ${sleep_secs}s (backoff=${backoff}, jitter=${jitter})..."
    sleep "$sleep_secs"
    attempt=$((attempt + 1))
  done

  if [ "$TIMED_OUT" -eq 1 ]; then
    break
  fi

  if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
    echo "❌ $NAME failed to become ready after $MAX_ATTEMPTS attempts"
    FAILED=1
  fi

  echo ""
done

if [ $FAILED -eq 1 ]; then
  if [[ -n "$COMPOSE_FILE" ]]; then
    echo "🔍 Checking Docker Compose container logs:"
    docker compose -f "$COMPOSE_FILE" logs --timestamps
    echo "🐳 Docker Compose container status:"
    docker compose -f "$COMPOSE_FILE" ps
  fi
  if [ "$TIMED_OUT" -eq 1 ]; then
    exit 124
  fi
  exit 1
fi

echo "✅ All endpoints are ready!"
