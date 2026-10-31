#!/usr/bin/env bash
# 03-paperclip/install-paperclip.sh
# Installs Paperclip (private-network mode, as a user service) plus the three
# local harness CLIs it will drive: Claude Code, Codex, and Pi.
#
# Interactive bits (the logins) are printed at the end; they can't be scripted.
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Guard: a stray DATABASE_URL in your shell will hijack onboarding"
if env | grep -qiE 'database_url|supabase|postgres_url'; then
  echo "!! Found a database variable in the environment. Run:"
  echo "   unset DATABASE_URL SUPABASE_URL SUPABASE_DB_URL POSTGRES_URL"
  echo "   then re-run this script."
  exit 1
fi

echo "==> Paperclip CLI"
cd "$(mktemp -d)"
curl -fsSLO https://paperclip.ing/install.sh
curl -fsSLO https://paperclip.ing/install.sh.sha256
sha256sum -c install.sh.sha256
bash install.sh            # answer Yes to adding ~/.local/bin to PATH
export PATH="$HOME/.local/bin:$PATH"
paperclipai --version

echo "==> Onboard: quickstart defaults + LAN reachability (authenticated/private mode)"
paperclipai onboard --yes --bind lan || true
paperclipai allowed-hostname "$DEVCO_LAN_IP" || true
paperclipai allowed-hostname "$(hostname)" || true

echo "==> Run as a user service that survives logout"
paperclipai service install --enable-linger || paperclipai service install
paperclipai service restart
paperclipai service status || true

echo "==> Harness CLIs (installed on THIS machine, because Paperclip drives local CLIs)"
sudo npm install -g @anthropic-ai/claude-code @openai/codex @earendil-works/pi-coding-agent
claude --version
codex --version
pi --version || true

echo "==> Pi -> local gateway"
mkdir -p ~/.pi/agent
sed "s#__GATEWAY__#${MODEL_GATEWAY_URL}#g" "$HERE/pi-models.json" > ~/.pi/agent/models.json
cat ~/.pi/agent/models.json

echo "==> Repos directory, QA runner, helper scripts"
mkdir -p "$DEVCO_REPOS" /opt/devco/bin
install -m 0755 "$HERE/routines/qa-run.sh" /opt/devco/qa-run.sh
install -m 0755 "$HERE/routines/mirror-repos.sh" /opt/devco/bin/mirror-repos.sh
install -m 0755 "$HERE/clone-project.sh" /opt/devco/bin/clone-project.sh

cat <<EOF

=====================================================================
Paperclip is running. Finish these by hand (they need a browser/login):

 1. Open http://${DEVCO_LAN_IP}:3100 — create your account and click
    "Claim this instance". (Or: paperclipai auth bootstrap-ceo)

 2. Sign the harness CLIs in ON THIS BOX:
      claude          # Max plan login; needs v2.1.255+ for Fable 5.1 -> run: claude update
      codex login     # ChatGPT Plus login (device/browser flow)

 3. In Paperclip's first-run wizard: name the company, name the CEO,
    runtime = Claude Code. If the CEO's first run fails with
    "ACP agent reported a terminal access failure", that just means
    step 2 wasn't done yet. Do it, then Inbox -> Retry.

 4. Board -> Settings -> General:
      - Description: paste the company mission (agents/company-mission.md)
      - Hiring: turn ON "Require board approval for new hires"

 5. Agents -> <CEO> -> Instructions -> AGENTS.md -> Edit:
      paste agents/ceo-AGENTS.md at the BOTTOM (leave Paperclip's text).
      Harness/Runtime tab: set the CEO's model to  sonnet.

 6. GitHub as the bot:  bash 03-paperclip/github-setup.sh
    (needs the bot account + org invite done first: agents/github-access.md)

 7. Bring in the first project:  /opt/devco/bin/clone-project.sh peel --python
    then register it in Paperclip as it prints.

 8. Continue with 04-hermes/create-profiles.sh, then the hire tickets in
    agents/hire-tickets/ (paste each as a task assigned to the CEO).
=====================================================================
EOF
