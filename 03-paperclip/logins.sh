#!/usr/bin/env bash
# 03-paperclip/logins.sh
# The part of the setup that can't be unattended: four logins that each need a
# browser. This runs them back to back with device codes, so you can do all of
# them from your phone in about five minutes while sitting at the ssh session.
#
# Run as the normal user on the box, AFTER github-setup.sh has created the bot's
# SSH key (it prints the key to add during step 3 here).
set -uo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.local/bin:$PATH"

pause() { echo; read -r -p ">>> $1  [Enter to continue] " _; echo; }

cat <<'EOF'
=====================================================================
 Four logins. Each prints a URL and a code; open the URL on ANY device,
 enter the code, and sign in as the account named. Have these ready:

   1. Claude Code  -> your Claude account (Max plan)
   2. Codex CLI    -> your ChatGPT account (Plus)
   3. gh CLI       -> the BOT GitHub account (spidersnet-devco-bot)
   4. Paperclip    -> claim the instance in a browser (your account)
=====================================================================
EOF

pause "1/4 Claude Code: sign in as YOU. If it opens a URL you can't click, copy it to your phone."
claude --version
claude auth login 2>/dev/null || claude    # older/newer CLIs differ; either lands in the login flow
echo "   (if 'claude' dropped you into a chat after login, type /exit)"

pause "2/4 Codex: sign in as YOU (ChatGPT Plus). Device-code flow, no local browser needed."
codex --version
codex login --device-auth 2>/dev/null || codex login
codex login status || true

pause "3/4 gh: sign in as the BOT ($GITHUB_BOT_USER). Pick: GitHub.com -> SSH -> skip key -> web browser."
echo "   Bot's public key (add at github.com/settings/keys as the bot, if not done):"
cat "$HOME/.ssh/id_ed25519_devco_bot.pub" 2>/dev/null || echo "   (run 03-paperclip/github-setup.sh first)"
gh auth login --hostname github.com --git-protocol ssh --web
gh auth status || true
ssh -T git@github.com 2>&1 | head -1 || true

pause "4/4 Paperclip: open http://$DEVCO_LAN_IP:3100 in a browser, create your account, click 'Claim this instance'."
paperclipai service status 2>/dev/null | head -3 || true

cat <<EOF

=====================================================================
Logins done. Verify:
  claude --version            # >= 2.1.255 for Fable 5.1
  codex login status
  gh auth status              # Logged in as $GITHUB_BOT_USER
  gh repo list $GITHUB_ORG    # the org's repos the bot can see
Next: README Phase 2 by-hand steps (mission, hire approval, CEO AGENTS.md).
=====================================================================
EOF
