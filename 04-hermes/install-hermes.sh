#!/usr/bin/env bash
# 04-hermes/install-hermes.sh
# Installs Hermes Agent (Nous Research) for the current user, non-interactively.
# Idempotent: re-running updates an existing install.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

if command -v hermes >/dev/null 2>&1; then
  echo "==> hermes already installed: $(hermes --version 2>/dev/null | head -1 || true); updating"
  hermes update --yes >/dev/null 2>&1 || hermes update >/dev/null 2>&1 || echo "   (update skipped)"
else
  TMP="$(mktemp -d)"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$TMP/install.sh"
  echo "==> Downloaded installer to $TMP/install.sh; running it non-interactively"
  # --non-interactive: no prompts (the unattended bootstrap has no TTY)
  # --skip-browser / --skip-computer-use: the juniors do not get those toolsets
  bash "$TMP/install.sh" --non-interactive --skip-browser --skip-computer-use
fi

export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
command -v hermes >/dev/null || { echo "!! hermes not on PATH after install (expected ~/.local/bin/hermes)"; exit 1; }
hermes --version
mkdir -p /opt/devco
sed -i '/^hermes=/d' /opt/devco/versions.txt 2>/dev/null || true
echo "hermes=$(hermes --version 2>/dev/null | head -1) ($(date +%F))" >> /opt/devco/versions.txt

# PyYAML for the profile config merge in create-profiles.sh (python3-yaml comes from install-base.sh)
python3 -c "import yaml" 2>/dev/null || sudo apt-get install -y -q python3-yaml

cat <<'EOF'

Hermes installed. Do NOT run `hermes setup` for the default profile; the
company uses named profiles. Next:

  bash 04-hermes/create-profiles.sh
EOF
