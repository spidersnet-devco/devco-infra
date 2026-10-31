#!/usr/bin/env bash
# 03-paperclip/github-setup.sh
# Signs THIS BOX in to GitHub as the bot account and configures git so every
# commit the agents make is attributed to the bot, never to Geoff.
#
#   bash 03-paperclip/github-setup.sh --prepare   # gh CLI + SSH key only (the unattended bootstrap runs this)
#   bash 03-paperclip/github-setup.sh             # + git identity; prints the two login steps
#
# Prerequisites for the full run (done in a browser, by Geoff; agents/github-access.md):
#   1. The bot account exists on github.com (GITHUB_BOT_USER in devco.env) with 2FA.
#   2. It has been invited to the org as a Member and accepted the invite.
#   3. Logged in AS THE BOT: Settings -> Emails -> "Keep my email addresses private";
#      the <id>+<user>@users.noreply.github.com address goes in GITHUB_BOT_NOREPLY.
set -euo pipefail
source /opt/devco/devco.env
PREPARE=0; [[ "${1:-}" == "--prepare" ]] && PREPARE=1

echo "==> gh CLI (always from GitHub's apt repo: Ubuntu's own gh package is too old for 'gh search prs')"
if ! command -v gh >/dev/null 2>&1 || [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -y -q update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -y -q install gh
fi
gh --version | head -1

echo "==> SSH key for the bot (ed25519, no passphrase: this is a service identity)"
KEY="$HOME/.ssh/id_ed25519_devco_bot"
if [[ ! -f "$KEY" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -q -t ed25519 -N "" -C "${GITHUB_BOT_USER:-devco-bot}@$(hostname)" -f "$KEY"
fi
# Route all github.com SSH through this key.
if ! grep -qs "IdentityFile $KEY" ~/.ssh/config; then
  cat >> ~/.ssh/config <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
  chmod 600 ~/.ssh/config
fi
# GitHub's published ed25519 host key (https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
GH_HOSTKEY="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
touch ~/.ssh/known_hosts; chmod 600 ~/.ssh/known_hosts
grep -qsF "$GH_HOSTKEY" ~/.ssh/known_hosts || echo "$GH_HOSTKEY" >> ~/.ssh/known_hosts

if (( PREPARE )); then
  echo "==> prepared. Bot public key (add it to the bot's GitHub account later):"
  cat "$KEY.pub"
  exit 0
fi

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

STEP B — sign the gh CLI in as the bot (needs a browser on any device):

    gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web

    "Login with a web browser" -> enter the code at the URL shown, LOGGED IN AS THE BOT.
    (logins.sh runs this for you together with the other logins.)

STEP C — verify, back here:

    ssh -T git@github.com          # expect: Hi $GITHUB_BOT_USER! You've successfully authenticated
    gh auth status                 # expect: Logged in to github.com account $GITHUB_BOT_USER
    gh repo list $GITHUB_ORG       # expect: the org's repos the bot can see

If 'gh repo list' shows nothing, the bot isn't in the org yet or has no repo
access: org -> People -> invite $GITHUB_BOT_USER; then on each repo (or via a
team) give it Write. See 03-paperclip/agents/github-access.md.
=====================================================================
EOF
