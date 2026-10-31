#!/usr/bin/env bash
# 03-paperclip/install-paperclip.sh
# Installs Paperclip (private/authenticated mode, bound to the LAN, as a user service)
# plus the harness CLIs it will drive on this box: Codex and Pi (Claude Code is
# installed by 01-base/install-base.sh with Anthropic's native installer).
# Nothing here needs a browser; the logins come after (logins.sh).
#
#   bash 03-paperclip/install-paperclip.sh                # interactive-friendly
#   bash 03-paperclip/install-paperclip.sh --unattended   # what the bootstrap runs
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
UNATTENDED=0; [[ "${1:-}" == "--unattended" ]] && UNATTENDED=1

echo "==> Guard: a stray DATABASE_URL in your shell would hijack onboarding"
if env | grep -qiE '^(database_url|supabase|postgres_url)'; then
  echo "!! Found a database variable in the environment. Run:"
  echo "   unset DATABASE_URL SUPABASE_URL SUPABASE_DB_URL POSTGRES_URL"
  echo "   then re-run this script."
  exit 1
fi

echo "==> Paperclip CLI"
if ! command -v paperclipai >/dev/null 2>&1; then
  # Not via paperclip.ing/install.sh: on 2026-10-31 that script passed --no-prompt to the
  # published CLI (2026.1023.0), which only knows --yes -> "error: unknown option".
  # Doing what the script does ourselves avoids the mismatch: npx the published CLI and
  # let its `install` put the managed copy under ~/.paperclip and a shim in ~/.local/bin
  # (--yes also adds ~/.local/bin to PATH in ~/.bashrc without asking).
  # PAPERCLIP_INSTALL_VERSION pins a release when set in devco.env (recorded in versions.txt).
  SPEC="paperclipai@${PAPERCLIP_INSTALL_VERSION:-latest}"
  echo "    npx --yes $SPEC install --yes"
  npx --yes "$SPEC" install --yes
fi
export PATH="$HOME/.local/bin:$PATH"
paperclipai --version
sed -i '/^paperclip=/d' /opt/devco/versions.txt 2>/dev/null || true
echo "paperclip=$(paperclipai --version 2>/dev/null | head -1) ($(date +%F))" >> /opt/devco/versions.txt

echo "==> Onboard: quickstart defaults, reachable on the LAN (authenticated/private mode), as a user service"
if paperclipai service status >/dev/null 2>&1; then
  echo "    service already installed; leaving config alone"
else
  # --yes alone would start the server in the FOREGROUND and never return;
  # --install-service makes it install + start the background service instead.
  PAPERCLIP_NO_BROWSER=1 paperclipai onboard --yes --bind lan --install-service
fi
paperclipai allowed-hostname "$DEVCO_LAN_IP" >/dev/null 2>&1 || true
paperclipai allowed-hostname "$(hostname)" >/dev/null 2>&1 || true
paperclipai allowed-hostname "$(hostname).local" >/dev/null 2>&1 || true
paperclipai service status || true
for _ in $(seq 1 30); do curl -fsS "$PAPERCLIP_URL/api/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$PAPERCLIP_URL/api/health" >/dev/null 2>&1 && echo "    Paperclip answers at $PAPERCLIP_URL" || echo "!! Paperclip is not answering yet at $PAPERCLIP_URL (check: paperclipai service status)"

echo "==> Harness CLIs this box runs for Paperclip"
# Codex and Pi via npm, into the user prefix set by install-base.sh (never sudo npm).
npm install -g --no-fund --no-audit @openai/codex @earendil-works/pi-coding-agent >/dev/null
echo "    codex $(codex --version 2>/dev/null | head -1)"
echo "    pi    $(pi --version 2>/dev/null | head -1 || echo installed)"
if command -v claude >/dev/null 2>&1; then
  echo "    claude $(claude --version 2>/dev/null | head -1)"
else
  echo "    claude: installing with the native installer"
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "==> Pi -> local gateway (the Watchdog runs on devco/coder-fast)"
mkdir -p ~/.pi/agent
sed "s#__GATEWAY__#${MODEL_GATEWAY_URL}#g" "$HERE/pi-models.json" > ~/.pi/agent/models.json
echo "    ~/.pi/agent/models.json written (provider 'devco'; create-company.sh also passes it as PAPERCLIP_PI_PROVIDERS)"

echo "==> Repos directory, QA runner, helper scripts -> /opt/devco/bin"
mkdir -p "$DEVCO_REPOS" /opt/devco/bin /opt/devco/cache
install -m 0755 "$HERE/routines/qa-run.sh"        /opt/devco/bin/qa-run.sh
install -m 0755 "$HERE/routines/mirror-repos.sh"  /opt/devco/bin/mirror-repos.sh
install -m 0755 "$HERE/clone-project.sh"          /opt/devco/bin/clone-project.sh
install -m 0755 "$HERE/create-company.sh"         /opt/devco/bin/create-company.sh
install -m 0755 "$HERE/lockdown.sh"               /opt/devco/bin/lockdown.sh
install -m 0755 "$HERE/../bin/devco"              /opt/devco/bin/devco
install -m 0755 "$HERE/../bin/backup-devco.sh"    /opt/devco/bin/backup-devco.sh
install -m 0755 "$HERE/../05-expansion/wake-athena.sh"  /opt/devco/bin/wake-athena.sh
install -m 0755 "$HERE/../05-expansion/sleep-athena.sh" /opt/devco/bin/sleep-athena.sh
install -m 0755 "$HERE/tools/smoke.py"                  /opt/devco/bin/smoke.py
grep -q '/opt/devco/bin' ~/.bashrc || echo 'export PATH="/opt/devco/bin:$PATH"' >> ~/.bashrc
# create-company.sh needs the agents/ folder next to it
rm -rf /opt/devco/bin/agents /opt/devco/bin/routines
cp -r "$HERE/agents" "$HERE/routines" /opt/devco/bin/

(( UNATTENDED )) && { echo "==> install-paperclip.sh done (unattended)"; exit 0; }

cat <<EOF

=====================================================================
Paperclip is running at http://${DEVCO_LAN_IP}:3100 (LAN) — nothing is claimed yet.

Next, in this order:
  1. bash 03-paperclip/logins.sh        # Claude, Codex, GitHub-as-bot, Paperclip claim + CLI login
  2. bash 03-paperclip/create-company.sh  # builds the CEO, the team, budgets, routines from agents/
  3. /opt/devco/bin/clone-project.sh peel --python   # first project
=====================================================================
EOF
