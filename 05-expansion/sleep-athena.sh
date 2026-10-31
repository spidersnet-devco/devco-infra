#!/usr/bin/env bash
# /opt/devco/bin/sleep-athena.sh — clear the local gateway's "athena" profile (so
# coder-fast is served locally again), then suspend Athena over SSH.
#
# The authorized_keys entry on Athena should be a restricted key:
#   command="sudo systemctl suspend",no-pty,no-port-forwarding,no-agent-forwarding ssh-ed25519 AAAA... devco-ops
# and /etc/sudoers.d/devco on Athena:  <user> ALL=(root) NOPASSWD: /usr/bin/systemctl suspend
set -euo pipefail
[[ -f /opt/devco/devco.env ]] && source /opt/devco/devco.env

ATHENA_SSH="${ATHENA_SSH:-ops@athena.lan}"
ATHENA_HEALTH="${ATHENA_HEALTH:-http://athena.lan:8080/health}"
LOCAL_GATEWAY="${MODEL_GATEWAY_URL:-http://127.0.0.1:8080/v1}"; LOCAL_GATEWAY="${LOCAL_GATEWAY%/v1}"

# Always route locally first, so no request is in flight to a machine going to sleep.
curl -fsS -X PUT "$LOCAL_GATEWAY/api/profiles/active" -H 'Content-Type: application/json' \
  -d '{"name":null}' >/dev/null 2>&1 && echo "athena: gateway profile cleared (coder-fast -> local)" || true

if ! curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; then
  echo "athena: already down"; exit 0
fi

echo "athena: suspending"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$ATHENA_SSH" true || { echo "athena: ssh failed"; exit 1; }
echo "athena: suspend sent"
