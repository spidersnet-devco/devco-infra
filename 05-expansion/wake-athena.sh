#!/usr/bin/env bash
# /opt/devco/bin/wake-athena.sh — Wake-on-LAN Athena and wait until its gateway answers.
# Exit 0 when healthy, 1 on timeout. Safe to run when it's already awake.
set -euo pipefail

ATHENA_MAC="${ATHENA_MAC:-aa:bb:cc:dd:ee:ff}"      # <- fill in
ATHENA_HEALTH="${ATHENA_HEALTH:-http://athena.lan:8080/health}"
TIMEOUT="${TIMEOUT:-300}"                          # seconds

if curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; then
  echo "athena: already up"; exit 0
fi

echo "athena: sending magic packet to $ATHENA_MAC"
wakeonlan "$ATHENA_MAC" >/dev/null

t=0
until curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; do
  sleep 5; t=$((t+5))
  if (( t >= TIMEOUT )); then echo "athena: no response after ${TIMEOUT}s"; exit 1; fi
done
echo "athena: up after ${t}s"
