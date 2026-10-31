#!/usr/bin/env bash
# 00-unattended/devco-bootstrap.sh
# Staged first-boot bootstrap, run by devco-bootstrap.service as the normal user.
# Stage file: /opt/devco/.bootstrap-stage   (0 -> 1 -> done)
#
#   stage 0 (1st boot): base packages, devco.env with detected LAN IP, kernel
#                       params, then reboot
#   stage 1 (2nd boot): verify GTT, build llama.cpp, download models, install
#                       and start the llama-swap gateway, then mark done
#
# Idempotent: re-running a stage is safe. A failure leaves the stage unchanged
# and writes /opt/devco/.bootstrap-FAILED with the reason; the service does not
# retry on its own (fix, then: sudo systemctl start devco-bootstrap).
set -euo pipefail

REPO="$HOME/devco-infra"
STAGE_FILE="/opt/devco/.bootstrap-stage"
FAIL_FILE="/opt/devco/.bootstrap-FAILED"
log() { echo "[$(date '+%F %T')] devco-bootstrap: $*"; }
fail() { log "FAILED: $*"; echo "$(date '+%F %T') $*" > "$FAIL_FILE"; exit 1; }
trap 'rc=$?; [[ $rc -ne 0 ]] && echo "$(date "+%F %T") exit $rc at stage $(cat "$STAGE_FILE" 2>/dev/null)" >> "$FAIL_FILE"' EXIT

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"   # pipx (hf CLI), npm globals
cd "$REPO" || fail "repo not found at $REPO"
STAGE="$(cat "$STAGE_FILE" 2>/dev/null || echo 0)"
rm -f "$FAIL_FILE"
log "starting, stage=$STAGE, user=$USER"

# Wait for DNS/network (network-online can fire before DNS works on first boot)
for _ in $(seq 1 60); do getent hosts github.com >/dev/null 2>&1 && break; sleep 5; done
getent hosts github.com >/dev/null 2>&1 || fail "no network after 5 minutes"

git pull -q --ff-only || log "git pull failed (offline or private); continuing with the installed copy"

case "$STAGE" in
  0)
    log "stage 0: base packages"
    bash 01-base/install-base.sh

    log "stage 0: devco.env with detected LAN IP"
    LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
    if [[ -n "$LAN_IP" ]]; then
      sed -i "s|^DEVCO_LAN_IP=.*|DEVCO_LAN_IP=\"$LAN_IP\"|" /opt/devco/devco.env
      log "  DEVCO_LAN_IP=$LAN_IP"
    fi
    sed -i "s|^DEVCO_USER=.*|DEVCO_USER=\"$USER\"|" /opt/devco/devco.env

    log "stage 0: kernel parameters"
    bash 01-base/apply-kernel-params.sh

    # The installer may have saved the autoinstall config (with the repo token
    # and password hash) into the installed system. Remove it.
    sudo rm -f /var/log/installer/autoinstall-user-data 2>/dev/null || true

    echo 1 > "$STAGE_FILE"
    log "stage 0 done; rebooting for kernel parameters"
    sudo systemctl reboot
    ;;

  1)
    log "stage 1: verify GTT"
    GTT="$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | sort -n | tail -1 || echo 0)"
    log "  mem_info_gtt_total=$GTT"
    [[ "${GTT:-0}" -gt 100000000000 ]] || fail "GTT is $GTT bytes; kernel params did not apply (see 01-base/strix-halo-kernel.md)"

    log "stage 1: llama.cpp (Vulkan)"
    bash 02-models/install-llamacpp.sh

    log "stage 1: models (~80 GB; this is the long part)"
    bash 02-models/download-models.sh

    log "stage 1: llama-swap gateway"
    bash 02-models/install-llama-swap.sh

    touch /opt/devco/.bootstrap-done
    echo done > "$STAGE_FILE"
    sudo systemctl disable devco-bootstrap.service >/dev/null 2>&1 || true
    log "stage 1 done. Gateway: http://127.0.0.1:8080/ui  Next: README Phase 2 (Paperclip)"
    ;;

  done)
    log "already done; nothing to do"
    ;;
  *)
    fail "unknown stage '$STAGE'"
    ;;
esac
