#!/usr/bin/env bash
# 01-base/install-base.sh
# Base packages for the MS-S1 Max (Ubuntu/Debian). Run once as your normal user.
#
#   bash 01-base/install-base.sh
#
# Fedora users: see the apt→dnf notes at the bottom of this file.
set -euo pipefail

echo "==> Base packages"
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake git curl wget jq unzip \
  python3 python3-pip python3-venv pipx \
  libvulkan-dev glslc vulkan-tools mesa-vulkan-drivers \
  libcurl4-openssl-dev \
  wakeonlan

echo "==> Node.js 24 (Paperclip needs 24.11+)"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh
  sudo -E bash /tmp/nodesource_setup.sh
  sudo apt-get install -y nodejs
fi
node -v

echo "==> pnpm (only needed if you ever build Paperclip from source)"
command -v pnpm >/dev/null 2>&1 || sudo npm install -g pnpm

echo "==> Hugging Face CLI (model downloads)"
pipx install -f "huggingface_hub[cli]" || pip3 install --user -U "huggingface_hub[cli]"

echo "==> Directories"
sudo mkdir -p /opt/devco /opt/devco/repos /opt/models /opt/llama-swap /opt/llama.cpp
sudo chown -R "$USER":"$USER" /opt/devco /opt/models /opt/llama-swap /opt/llama.cpp

if [[ ! -f /opt/devco/devco.env ]]; then
  cp "$(dirname "$0")/../devco.env.example" /opt/devco/devco.env
  echo "    Wrote /opt/devco/devco.env — EDIT DEVCO_LAN_IP before continuing."
fi

echo "==> GPU access groups (log out and back in afterwards)"
sudo usermod -aG video,render "$USER"

echo "==> Keep user services running without a login session"
sudo loginctl enable-linger "$USER"

cat <<'EOF'

Done. NEXT:
  1. Edit /opt/devco/devco.env  (at minimum DEVCO_LAN_IP)
  2. Apply the kernel parameters in 01-base/strix-halo-kernel.md and reboot.
  3. Then run 02-models/install-llamacpp.sh

Fedora notes:
  dnf install -y vulkan-headers vulkan-loader-devel mesa-vulkan-drivers cmake gcc-c++ git \
                 python3-pip pipx nodejs npm libcurl-devel
  (Fedora 42+ ships a Mesa new enough for the Radeon 8060S; on Ubuntu you want
   25.04 or newer, or 24.04 with the HWE stack and a Mesa 25 PPA.)
EOF
