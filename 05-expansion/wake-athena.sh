#!/usr/bin/env bash
# /opt/devco/bin/wake-athena.sh — Wake-on-LAN Athena, wait until its gateway answers,
# then switch the local gateway's "athena" profile on so coder-fast goes there.
# Exit 0 when healthy, 1 on timeout. Safe to run when it's already awake.
set -euo pipefail
[[ -f /opt/devco/devco.env ]] && source /opt/devco/devco.env

ATHENA_MAC="${ATHENA_MAC:-}"                                  # set in /opt/devco/devco.env
ATHENA_HEALTH="${ATHENA_HEALTH:-http://athena.lan:8080/health}"
LOCAL_GATEWAY="${MODEL_GATEWAY_URL:-http://127.0.0.1:8080/v1}"; LOCAL_GATEWAY="${LOCAL_GATEWAY%/v1}"
TIMEOUT="${TIMEOUT:-300}"                                     # seconds

[[ -n "$ATHENA_MAC" ]] || { echo "athena: ATHENA_MAC is not set in /opt/devco/devco.env"; exit 2; }

activate_profile() {
  curl -fsS -X PUT "$LOCAL_GATEWAY/api/profiles/active" -H 'Content-Type: application/json' \
    -d '{"name":"athena"}' >/dev/null && echo "athena: gateway profile 'athena' active (coder-fast -> Athena)"
}

if curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; then
  echo "athena: already up"; activate_profile; exit 0
fi

echo "athena: sending magic packet to $ATHENA_MAC"
wakeonlan "$ATHENA_MAC" >/dev/null

t=0
until curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; do
  sleep 5; t=$((t+5))
  if (( t >= TIMEOUT )); then echo "athena: no response after ${TIMEOUT}s"; exit 1; fi
done
echo "athena: up after ${t}s"
activate_profile
