#!/usr/bin/env bash
# 02-models/install-llamacpp.sh
# Builds llama.cpp with the Vulkan backend into /opt/llama.cpp (default), or
# pulls the community Strix Halo toolbox container with --container.
#
#   bash 02-models/install-llamacpp.sh              # host build (Vulkan/RADV)
#   bash 02-models/install-llamacpp.sh --container  # podman toolbox instead
set -euo pipefail
source /opt/devco/devco.env

MODE="${1:-host}"

if [[ "$MODE" == "--container" ]]; then
  echo "==> Pulling kyuz0 Strix Halo toolbox (Vulkan RADV)"
  command -v podman >/dev/null || sudo apt-get install -y podman
  podman pull docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv
  cat <<EOF

Container pulled. In llama-swap.yaml, replace the 'llama' macro with:

  "llama": >
    podman run --rm --name \${MODEL_ID} --device /dev/dri --device /dev/kfd
    --network host -v ${DEVCO_MODELS}:/models
    docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv
    llama-server --host 127.0.0.1 --port \${PORT}

and add   cmdStop: podman stop \${MODEL_ID}   to each model.
EOF
  exit 0
fi

echo "==> Building llama.cpp (Vulkan) into /opt/llama.cpp"
cd /opt/llama.cpp
if [[ ! -d src ]]; then
  git clone https://github.com/ggml-org/llama.cpp.git src
fi
cd src
git pull --ff-only
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=ON
cmake --build build --config Release -j"$(nproc)"

ln -sfn /opt/llama.cpp/src/build/bin /opt/llama.cpp/bin
echo "==> Installed: /opt/llama.cpp/bin/llama-server"

echo "==> Sanity check (expect a 'Radeon 8060S ... (RADV GFX1151)' line)"
/opt/llama.cpp/bin/llama-server --version 2>&1 | head -5 || true
vulkaninfo --summary 2>/dev/null | grep -iE "8060S|GFX1151" || \
  echo "!! Vulkan does not see the 8060S. Check 01-base/strix-halo-kernel.md (Mesa version)."

cat <<'EOF'

Rebuild later with:  bash 02-models/install-llamacpp.sh
Next:                bash 02-models/download-models.sh
EOF
