#!/usr/bin/env bash
# 01-base/install-base.sh
# Base packages and tooling for the MS-S1 Max (Ubuntu 26.04 LTS Server).
# Run once as your normal user (the unattended bootstrap runs it on first boot).
# Idempotent: safe to re-run.
#
#   bash 01-base/install-base.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# `sudo env ...` instead of `sudo -E`: 26.04's default sudo (sudo-rs) ignores -E.
# The lock timeout makes apt wait for apt-daily/unattended-upgrades instead of failing.
APT=(sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=600 -y -q)

echo "==> Base packages"
"${APT[@]}" update
"${APT[@]}" install \
  build-essential cmake git curl wget jq unzip ca-certificates gnupg \
  python3 python3-pip python3-venv python3-yaml pipx \
  libvulkan-dev glslc spirv-headers vulkan-tools mesa-vulkan-drivers libssl-dev \
  shellcheck tidy avahi-daemon wakeonlan \
  docker.io docker-compose-v2

# Qt runtime libraries so PySide6 test suites run headless (QT_QPA_PLATFORM=offscreen).
# Best effort: a renamed package must not stop the first boot.
echo "==> Qt/X11 runtime libs for headless PySide6 tests (best effort)"
"${APT[@]}" install --no-install-recommends \
  libegl1 libgl1 libopengl0 libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 libfontconfig1 \
  libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
  libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 libxcb-xfixes0 libxcb-randr0 libxcb-shm0 \
  libxcb-sync1 libxrender1 libxi6 libsm6 libice6 libglib2.0-0t64 \
  || echo "   (some Qt runtime libs did not install; PySide6 tests may need them later)"

echo "==> Node.js 24 (Paperclip needs >= 24.11)"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 24 ]]; then
  TMP="$(mktemp -d)"
  curl -fsSL https://deb.nodesource.com/setup_24.x -o "$TMP/nodesource_setup.sh"
  sudo bash "$TMP/nodesource_setup.sh"          # plain sudo: 26.04's sudo-rs ignores -E
  "${APT[@]}" install nodejs
fi
node -v

echo "==> npm: install global packages into the user's home, never with sudo"
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
grep -q 'npm-global' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

echo "==> Claude Code (native installer; auto-updates itself, needs no sudo)"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
claude --version || echo "   (claude not on PATH yet; open a new shell)"

echo "==> Python CLIs: hf (model downloads, via pipx) and Playwright (web smoke tests, own venv)"
pipx install huggingface_hub >/dev/null 2>&1 || pipx upgrade huggingface_hub >/dev/null 2>&1 || true
pipx ensurepath >/dev/null 2>&1 || true
command -v hf >/dev/null 2>&1 && echo "    hf: $(hf version 2>/dev/null | head -1)"
# A shared tool venv for scripts the agents run (PEP 668 forbids pip --user on 26.04).
sudo mkdir -p /opt/devco && sudo chown "$USER":"$USER" /opt/devco
[[ -x /opt/devco/venv/bin/python ]] || python3 -m venv /opt/devco/venv
/opt/devco/venv/bin/pip install -q -U pip playwright pyyaml >/dev/null 2>&1 || echo "   (pip install into /opt/devco/venv failed; offline?)"
if [[ -x /opt/devco/venv/bin/playwright && ! -d "$HOME/.cache/ms-playwright" ]]; then
  echo "    Chromium for Playwright (~170 MB) plus its system libraries"
  sudo /opt/devco/venv/bin/playwright install-deps chromium 2>&1 | tail -n 2 || true
  /opt/devco/venv/bin/playwright install chromium 2>&1 | tail -n 2 || echo "   (chromium download failed; webby's browser-smoke-test skill retries it)"
fi

echo "==> Directories"
sudo mkdir -p /opt/devco /opt/devco/repos /opt/devco/bin /opt/models /opt/llama-swap /opt/llama.cpp
sudo chown -R "$USER":"$USER" /opt/devco /opt/models /opt/llama-swap /opt/llama.cpp

if [[ ! -f /opt/devco/devco.env ]]; then
  cp "$HERE/../devco.env.example" /opt/devco/devco.env
  chmod 600 /opt/devco/devco.env
  echo "    Wrote /opt/devco/devco.env (edit DEVCO_LAN_IP if the bootstrap did not)."
fi

echo "==> Git identity (provisional; 03-paperclip/github-setup.sh replaces it with the bot's)"
if [[ -z "$(git config --global user.email || true)" ]]; then
  git config --global user.name  "devco-setup"
  git config --global user.email "devco-setup@$(hostname)"
  git config --global init.defaultBranch main
  git config --global pull.ff only
fi

echo "==> GPU access groups (takes effect at next login; services get it via linger)"
sudo usermod -aG video,render "$USER"

echo "==> Keep user services running without a login session"
sudo loginctl enable-linger "$USER"

echo "==> Swap: 16 GB file as OOM insurance (the GPU can pin ~124 GiB of RAM)"
SWAP_GB="$(free -g | awk '/^Swap:/{print $2}')"
if (( SWAP_GB < 12 )) && [[ ! -f /swapfile.devco ]]; then
  sudo fallocate -l 16G /swapfile.devco && sudo chmod 600 /swapfile.devco && sudo mkswap -q /swapfile.devco
  sudo swapon /swapfile.devco
  grep -q '/swapfile.devco' /etc/fstab || echo '/swapfile.devco none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi
free -h | sed -n '1,3p'

cat <<'EOF'

Done. NEXT (by hand; the unattended bootstrap does these for you):
  1. Check /opt/devco/devco.env  (DEVCO_LAN_IP)
  2. bash 01-base/apply-kernel-params.sh && sudo reboot
  3. bash 02-models/install-llamacpp.sh
EOF
