#!/usr/bin/env bash
# 03-paperclip/logins.sh
# The part of the setup that can't be unattended: five logins that each need a
# browser. Runs them back to back with device codes / approval links, so you can do
# all of them from your phone in about five minutes while sitting at the ssh session.
#
# Run as the normal user on the box, after the unattended bootstrap finished (or after
# install-paperclip.sh + github-setup.sh --prepare by hand).
set -uo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

pause() { echo; read -r -p ">>> $1  [Enter to continue, s to skip] " a; echo; [[ "${a:-}" != "s" ]]; }

cat <<'EOF'
=====================================================================
 Five logins. Each prints a URL and a code; open the URL on ANY device,
 enter the code, and sign in as the account named. Have these ready:

   1. Claude Code   -> your Claude account (Max plan)
   2. Codex CLI     -> your ChatGPT account (Plus)
   3. gh CLI        -> the BOT GitHub account (spidersnet-devco-bot)
   4. Paperclip     -> claim the instance in a browser (creates your board account)
   5. Paperclip CLI -> approve the CLI's access in that same browser
=====================================================================
EOF

if pause "1/5 Claude Code: sign in as YOU (Max). If a URL can't be clicked here, copy it to your phone."; then
  claude --version
  claude auth login || echo "   (if that command is unknown on this version, run: claude   and type /login, then /exit)"
  claude auth status 2>/dev/null || true
fi

if pause "2/5 Codex: sign in as YOU (ChatGPT Plus). Device-code flow, no local browser needed."; then
  codex --version
  codex login --device-auth || codex login
  codex login status || true
fi

if pause "3/5 gh: sign in as the BOT ($GITHUB_BOT_USER). First add the key below at github.com/settings/keys AS THE BOT."; then
  echo "   Bot's public key:"; cat "$HOME/.ssh/id_ed25519_devco_bot.pub" 2>/dev/null || echo "   (run 03-paperclip/github-setup.sh --prepare first)"
  echo
  gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web
  gh auth status || true
  ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | head -1 || true
  if [[ -n "${GITHUB_BOT_NOREPLY:-}" ]]; then bash "$(dirname "$0")/github-setup.sh" >/dev/null && echo "   git identity set to the bot"; else
    echo "   !! GITHUB_BOT_NOREPLY is empty in /opt/devco/devco.env: set it, then run 03-paperclip/github-setup.sh"; fi
fi

if pause "4/5 Paperclip: open http://$DEVCO_LAN_IP:3100 in a browser, create your account, click 'Claim this instance'. Skip the wizard's 'first task' if it offers one."; then
  paperclipai service status 2>/dev/null | head -3 || true
fi

if pause "5/5 Paperclip CLI: this prints an approval link. It says 127.0.0.1; open it in the browser where you are signed in to Paperclip with 127.0.0.1 replaced by $DEVCO_LAN_IP (keep the ?token= part), then approve."; then
  paperclipai auth login --api-base "$PAPERCLIP_URL" && paperclipai auth whoami --api-base "$PAPERCLIP_URL"
fi

cat <<EOF

=====================================================================
Logins done. Verify:
  claude --version            # >= 2.1.257 for Fable 5.1
  codex login status
  gh auth status              # Logged in as $GITHUB_BOT_USER
  gh repo list $GITHUB_ORG    # the org's repos the bot can see
  paperclipai auth whoami --api-base $PAPERCLIP_URL

Next:  bash 03-paperclip/create-company.sh     (README Phase 2)
=====================================================================
EOF
