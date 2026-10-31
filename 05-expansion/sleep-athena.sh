#!/usr/bin/env bash
# /opt/devco/bin/sleep-athena.sh — suspend Athena over SSH (restricted key).
# The authorized_keys entry on Athena should be:
#   command="sudo systemctl suspend",no-pty,no-port-forwarding ssh-ed25519 AAAA... devco-ops
# and /etc/sudoers.d/devco:  <user> ALL=(root) NOPASSWD: /usr/bin/systemctl suspend
set -euo pipefail

ATHENA_SSH="${ATHENA_SSH:-ops@athena.lan}"
ATHENA_HEALTH="${ATHENA_HEALTH:-http://athena.lan:8080/health}"

if ! curl -fsS -m 3 "$ATHENA_HEALTH" >/dev/null 2>&1; then
  echo "athena: already down"; exit 0
fi

echo "athena: suspending"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$ATHENA_SSH" true || { echo "athena: ssh failed"; exit 1; }
echo "athena: suspend sent"
