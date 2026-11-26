#!/usr/bin/env bash
# Retry only observed Maven/Gradle HTTP 429 network throttling.
# All analysis, tests, normal build errors and final failure remain blocking.
set -euo pipefail
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
for attempt in 1 2; do
  if flutter build apk "$@" 2>&1 | tee "$log"; then
    exit 0
  fi
  if [ "$attempt" -eq 2 ] || ! grep -Eq 'Received status code 429|HTTP (status )?429|429 Too Many Requests' "$log"; then
    exit 1
  fi
  echo 'Maven/Gradle throttled dependency download; retrying once after backoff.'
  sleep 45
done
exit 1
