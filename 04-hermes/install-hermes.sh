#!/usr/bin/env bash
# 04-hermes/install-hermes.sh
# Installs Hermes Agent (Nous Research) for the current user.
set -euo pipefail

if command -v hermes >/dev/null 2>&1; then
  echo "hermes already installed: $(hermes --version 2>/dev/null || true)"
  echo "updating..."; hermes update || true
  exit 0
fi

TMP="$(mktemp -d)"
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o "$TMP/install.sh"
echo "==> Downloaded installer to $TMP/install.sh (read it if you like), running it..."
bash "$TMP/install.sh"

export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
hermes --version

# PyYAML for the profile config merge in create-profiles.sh
python3 -c "import yaml" 2>/dev/null || pip3 install --user pyyaml

cat <<'EOF'

Hermes installed. Do NOT run `hermes setup` for the default profile; the
company uses named profiles. Next:

  bash 04-hermes/create-profiles.sh
EOF
