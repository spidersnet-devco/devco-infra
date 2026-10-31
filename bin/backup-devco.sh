#!/usr/bin/env bash
# /opt/devco/bin/backup-devco.sh — back up the state that is NOT in GitHub:
#   - Paperclip's database (tasks, agents, config, costs)    via paperclipai db:backup
#   - Hermes profiles (configs, SOULs, the skills the juniors wrote, memories)
#   - /opt/devco (devco.env, versions.txt, cache excluded) and the gateway config
# into $DEVCO_BACKUP_DIR (default: $GIT_MIRROR_DIR/../devco-backups, i.e. the same NAS
# share as the repo mirror), keeping the last 14. Schedule with:
#   devco backup --install-timer      (daily 04:00 as a systemd user timer)
set -euo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

if [[ "${1:-}" == "--install-timer" ]]; then
  mkdir -p ~/.config/systemd/user
  printf '[Unit]\nDescription=devco state backup\n[Service]\nType=oneshot\nExecStart=/opt/devco/bin/backup-devco.sh\n' > ~/.config/systemd/user/devco-backup.service
  printf '[Unit]\nDescription=Daily devco backup\n[Timer]\nOnCalendar=*-*-* 04:00:00\nPersistent=true\n[Install]\nWantedBy=timers.target\n' > ~/.config/systemd/user/devco-backup.timer
  systemctl --user daemon-reload && systemctl --user enable --now devco-backup.timer
  systemctl --user list-timers devco-backup.timer --no-pager; exit 0
fi

DEST="${DEVCO_BACKUP_DIR:-}"
if [[ -z "$DEST" ]]; then
  [[ -n "${GIT_MIRROR_DIR:-}" ]] || { echo "backup: set DEVCO_BACKUP_DIR (or GIT_MIRROR_DIR) in devco.env"; exit 2; }
  DEST="$(dirname "$GIT_MIRROR_DIR")/devco-backups"
fi
if ! findmnt -T "$(dirname "$DEST")" >/dev/null 2>&1 && [[ "${DEVCO_BACKUP_REQUIRE_MOUNT:-1}" == "1" ]]; then
  echo "backup: $DEST is not on a mounted share (DEVCO_BACKUP_REQUIRE_MOUNT=0 to allow local)"; exit 2
fi
STAMP="$(date +%F_%H%M)"
OUT="$DEST/$STAMP"; mkdir -p "$OUT"

echo "==> Paperclip database"
if command -v paperclipai >/dev/null; then
  paperclipai db:backup --dir "$OUT/paperclip-db" --retention-days 30 >/dev/null 2>&1 \
    || { tar -C "$HOME" -czf "$OUT/paperclip-home.tgz" --exclude='*/node_modules' .paperclip 2>/dev/null && echo "    (db:backup unavailable; archived ~/.paperclip instead)"; }
fi

echo "==> Hermes profiles"
[[ -d "$HOME/.hermes" ]] && tar -C "$HOME" -czf "$OUT/hermes.tgz" --exclude='.hermes/**/node_modules' --exclude='.hermes/**/.venv' .hermes

echo "==> /opt/devco (no cache) + gateway config"
tar -C / -czf "$OUT/opt-devco.tgz" --exclude='opt/devco/cache' --exclude='opt/devco/repos' opt/devco opt/llama-swap/config.yaml 2>/dev/null || true

echo "==> Prune: keep the newest 14"
ls -1d "$DEST"/*/ 2>/dev/null | sort | head -n -14 | xargs -r rm -rf

du -sh "$OUT" | sed 's/^/backup: /'
