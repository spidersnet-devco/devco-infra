#!/usr/bin/env bash
# 03-paperclip/github-setup.sh
# Signs THIS BOX in to GitHub as the bot account and configures git so every
# commit the agents make is attributed to the bot, never to Geoff.
#
# Prerequisites (done in a browser, by Geoff):
#   1. The bot account exists on github.com (GITHUB_BOT_USER in devco.env) with
#      its own email and 2FA turned on.
#   2. It has been invited to the org as a Member and accepted the invite.
#   3. Logged in AS THE BOT: Settings -> Emails -> tick "Keep my email addresses
#      private" and copy the <id>+<user>@users.noreply.github.com address into
#      GITHUB_BOT_NOREPLY in /opt/devco/devco.env.
#
# Two logins happen here and both need a browser (any device):
#   - SSH key: this script prints a public key; add it at github.com/settings/keys
#     while logged in as the bot.
#   - gh CLI: `gh auth login` shows a one-time code; enter it at the URL it prints,
#     logged in as the bot. This is what lets agents run `gh pr create`.
set -euo pipefail
source /opt/devco/devco.env

echo "==> gh CLI"
if ! command -v gh >/dev/null 2>&1; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update && sudo apt-get install -y gh
fi
gh --version | head -1

echo "==> SSH key for the bot (ed25519, no passphrase: this is a service identity)"
KEY="$HOME/.ssh/id_ed25519_devco_bot"
if [[ ! -f "$KEY" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -N "" -C "$GITHUB_BOT_USER@$(hostname)" -f "$KEY"
fi
# Route all github.com SSH through this key.
if ! grep -q "IdentityFile $KEY" ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
  chmod 600 ~/.ssh/config
fi
ssh-keyscan -t ed25519 github.com 2>/dev/null >> ~/.ssh/known_hosts || true

echo "==> Global git identity = the bot"
if [[ -z "${GITHUB_BOT_NOREPLY:-}" ]]; then
  echo "!! GITHUB_BOT_NOREPLY is empty in /opt/devco/devco.env."
  echo "   Log in to github.com AS THE BOT -> Settings -> Emails -> tick 'Keep my email"
  echo "   addresses private' -> copy the users.noreply.github.com address into devco.env,"
  echo "   then re-run this script."
  exit 1
fi
git config --global user.name  "$GITHUB_BOT_USER"
git config --global user.email "$GITHUB_BOT_NOREPLY"
git config --global init.defaultBranch main
git config --global pull.ff only
git config --global push.autoSetupRemote true
git config --global --list | grep -E '^user\.|^init\.|^push\.'

cat <<EOF

=====================================================================
STEP A — add this public key to the BOT account (github.com/settings/keys,
         logged in as $GITHUB_BOT_USER), title: $(hostname)

$(cat "$KEY.pub")

STEP B — sign the gh CLI in as the bot. Run this yourself (it needs a browser):

    gh auth login --hostname github.com --git-protocol ssh --web

    Pick: GitHub.com -> SSH -> skip adding a key (already done) -> Login with a
    web browser -> enter the code at the URL shown, LOGGED IN AS THE BOT.

STEP C — verify, back here:

    ssh -T git@github.com          # expect: Hi $GITHUB_BOT_USER! You've successfully authenticated
    gh auth status                 # expect: Logged in to github.com account $GITHUB_BOT_USER
    gh repo list $GITHUB_ORG       # expect: the org's repos the bot can see

If 'gh repo list' shows nothing, the bot isn't in the org yet or has no repo
access: org -> People -> invite $GITHUB_BOT_USER; then on each repo (or via a
team) give it Write. See 03-paperclip/agents/github-access.md.
=====================================================================
EOF
