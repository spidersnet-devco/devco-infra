#!/usr/bin/env bash
# 00-unattended/devco-bootstrap.sh
# Staged first-boot bootstrap, run by devco-bootstrap.service as the normal user.
# Stage file: /opt/devco/.bootstrap-stage   (0 -> 1 -> 2 -> done)
#
#   stage 0 (1st boot): base packages, devco.env with detected LAN IP, kernel
#                       params, then reboot
#   stage 1 (2nd boot): verify GTT, build llama.cpp, download models, install
#                       and start the llama-swap gateway
#   stage 2 (same boot): everything else that needs no login: Paperclip (as a
#                       user service), the harness CLIs, Hermes + the three
#                       profiles, gh + the bot's SSH key. Then mark done.
#
# Idempotent: re-running a stage is safe. A failure leaves the stage unchanged
# and writes /opt/devco/.bootstrap-FAILED with the reason; the service does not
# retry on its own (fix, then: sudo systemctl start --no-block devco-bootstrap).
set -euo pipefail

REPO="$HOME/devco-infra"
STAGE_FILE="/opt/devco/.bootstrap-stage"
FAIL_FILE="/opt/devco/.bootstrap-FAILED"
log() { echo "[$(date '+%F %T')] devco-bootstrap: $*"; }
fail() { log "FAILED: $*"; echo "$(date '+%F %T') $*" > "$FAIL_FILE"; exit 1; }
trap 'rc=$?; [[ $rc -ne 0 ]] && echo "$(date "+%F %T") exit $rc at stage $(cat "$STAGE_FILE" 2>/dev/null)" >> "$FAIL_FILE"' EXIT

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:$PATH"   # pipx, npm globals, claude
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
cd "$REPO" || fail "repo not found at $REPO"
STAGE="$(cat "$STAGE_FILE" 2>/dev/null || echo 0)"
rm -f "$FAIL_FILE"
log "starting, stage=$STAGE, user=$USER"

# Wait for DNS/network (network-online can fire before DNS works on first boot)
for _ in $(seq 1 60); do getent hosts github.com >/dev/null 2>&1 && break; sleep 5; done
getent hosts github.com >/dev/null 2>&1 || fail "no network after 5 minutes"

git pull -q --ff-only || log "git pull failed (offline or private); continuing with the installed copy"

stage0() {
  log "stage 0: base packages"
  bash 01-base/install-base.sh

  log "stage 0: devco.env with detected LAN IP"
  LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
  if [[ -n "$LAN_IP" ]]; then
    sed -i "s|^DEVCO_LAN_IP=.*|DEVCO_LAN_IP=\"$LAN_IP\"|" /opt/devco/devco.env
    log "  DEVCO_LAN_IP=$LAN_IP   (use this if hermes.local does not resolve)"
  fi
  sed -i "s|^DEVCO_USER=.*|DEVCO_USER=\"$USER\"|" /opt/devco/devco.env

  log "stage 0: kernel parameters"
  bash 01-base/apply-kernel-params.sh

  # The installer saves a copy of the autoinstall config into the installed
  # system (mode 0400 root); it holds the throwaway password hash, so remove it.
  sudo rm -f /var/log/installer/autoinstall-user-data 2>/dev/null || true

  echo 1 > "$STAGE_FILE"
  log "stage 0 done; rebooting for kernel parameters"
  trap - EXIT                      # the reboot SIGTERMs us; that is not a failure
  sudo systemctl reboot
  exit 0
}

stage1() {
  log "stage 1: verify GTT"
  GTT="$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | sort -n | tail -1 || echo 0)"
  log "  mem_info_gtt_total=$GTT"
  [[ "${GTT:-0}" -gt 100000000000 ]] || fail "GTT is $GTT bytes; kernel params did not apply (see 01-base/strix-halo-kernel.md)"

  log "stage 1: llama.cpp (Vulkan)"
  bash 02-models/install-llamacpp.sh

  log "stage 1: models (~86 GB; this is the long part)"
  bash 02-models/download-models.sh

  log "stage 1: llama-swap gateway"
  rc=0; bash 02-models/install-llama-swap.sh || rc=$?
  if (( rc == 3 )); then log "  gateway is up but the tool-calling smoke test failed; continuing (check http://127.0.0.1:8080/ui)"
  elif (( rc != 0 )); then fail "llama-swap install failed (exit $rc)"; fi

  echo 2 > "$STAGE_FILE"
  log "stage 1 done. Gateway: http://127.0.0.1:8080/ui"
}

stage2() {
  local failed=()
  step() {  # step <label> <command...>
    log "stage 2: $1"; shift
    if "$@"; then return 0; fi
    log "  !! step failed: $*"; failed+=("$*"); return 0
  }
  step "Paperclip + harness CLIs (unattended part)" bash 03-paperclip/install-paperclip.sh --unattended
  step "Hermes Agent"                               bash 04-hermes/install-hermes.sh
  step "Hermes profiles (pyro, webby, ops)"         bash 04-hermes/create-profiles.sh
  step "gh CLI + bot SSH key (no login yet)"        bash 03-paperclip/github-setup.sh --prepare

  if (( ${#failed[@]} )); then
    fail "stage 2: ${#failed[@]} step(s) failed: ${failed[*]} -- fix, then: sudo systemctl start --no-block devco-bootstrap"
  fi
  touch /opt/devco/.bootstrap-done
  echo "done" > "$STAGE_FILE"
  sudo systemctl disable devco-bootstrap.service >/dev/null 2>&1 || true
  log "stage 2 done. ALL UNATTENDED WORK FINISHED."
  log "Next (needs you): ssh in, then  bash ~/devco-infra/03-paperclip/logins.sh   (README Phase 2)"
}

case "$STAGE" in
  0)    stage0 ;;
  1)    stage1; stage2 ;;
  2)    stage2 ;;
  done) log "already done; nothing to do" ;;
  *)    fail "unknown stage '$STAGE'" ;;
esac
