#!/usr/bin/env bash
# 02-models/install-llamacpp.sh
# Builds llama.cpp with the Vulkan backend into /opt/llama.cpp (default), or
# pulls the community Strix Halo toolbox container with --container.
#
#   bash 02-models/install-llamacpp.sh                    # host build (Vulkan/RADV)
#   bash 02-models/install-llamacpp.sh --container        # kyuz0 toolbox, Vulkan
#   bash 02-models/install-llamacpp.sh --container rocm   # kyuz0 toolbox, ROCm 10.0
#
# The build is pinned to a release tag so a rebuild months later gets the same
# binary. LLAMACPP_TAG in /opt/devco/devco.env wins; otherwise the newest
# release tag is resolved and recorded in /opt/devco/versions.txt.
set -euo pipefail
source /opt/devco/devco.env

MODE="${1:-host}"
FLAVOR="${2:-vulkan}"

if [[ "$MODE" == "--container" ]]; then
  TAG="vulkan-radv"; [[ "$FLAVOR" == "rocm" ]] && TAG="rocm-10.0"
  echo "==> Pulling kyuz0 Strix Halo toolbox ($TAG)"
  command -v podman >/dev/null || sudo apt-get install -y podman
  podman pull "docker.io/kyuz0/amd-strix-halo-toolboxes:$TAG"
  cat <<EOF

Container pulled. In /opt/llama-swap/config.yaml replace the 'llama' macro with:

  "llama": >
    podman run --rm --name \${MODEL_ID} --network host
    --device /dev/dri --userns keep-id --group-add keep-groups --security-opt label=disable
    -v ${DEVCO_MODELS}:/opt/models:ro
    docker.io/kyuz0/amd-strix-halo-toolboxes:$TAG
    llama-server --host 127.0.0.1 --port \${PORT}
    -ngl 99 -fa on --load-mode none --cache-type-k q8_0 --cache-type-v q8_0
    -ub 2048 -b 2048 --cache-ram 2048 --metrics

and add   cmdStop: podman stop \${MODEL_ID}   to each model. (ROCm images also
need --device /dev/kfd.) ROCm wins prompt processing by 2-2.5x at 32-64K context;
Vulkan wins token generation and stability. Switch tags if long prompts become
the bottleneck.
EOF
  exit 0
fi

echo "==> Build dependencies check"
for p in cmake glslc; do command -v "$p" >/dev/null || { echo "!! $p missing; run 01-base/install-base.sh"; exit 1; }; done
dpkg -s spirv-headers libvulkan-dev libssl-dev >/dev/null 2>&1 || \
  { echo "!! spirv-headers/libvulkan-dev/libssl-dev missing; run 01-base/install-base.sh"; exit 1; }

echo "==> Source"
mkdir -p /opt/llama.cpp && cd /opt/llama.cpp
if [[ ! -d src/.git ]]; then
  git clone https://github.com/ggml-org/llama.cpp.git src
fi
cd src
git fetch -q --tags origin

TAG="${LLAMACPP_TAG:-}"
if [[ -z "$TAG" ]]; then
  # Newest release tag (b####). No GitHub API call, so no rate limit.
  TAG="$(git tag -l 'b[0-9]*' | sort -t b -k 2 -n | tail -1)"
fi
[[ -n "$TAG" ]] || { echo "!! could not resolve a llama.cpp tag"; exit 1; }
echo "==> Checking out llama.cpp $TAG"
git checkout -q "$TAG"

echo "==> Building (Vulkan). ~10 minutes on the MS-S1 Max."
# LLAMA_CURL is gone (HTTPS is OpenSSL now, default on). Tests/examples off: not needed.
cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
cmake --build build --config Release -j"$(nproc)" --target llama-server

ln -sfn /opt/llama.cpp/src/build/bin /opt/llama.cpp/bin
echo "==> Installed: /opt/llama.cpp/bin/llama-server"
mkdir -p /opt/devco
sed -i '/^llama.cpp=/d' /opt/devco/versions.txt 2>/dev/null || true
echo "llama.cpp=$TAG ($(date +%F))" >> /opt/devco/versions.txt

echo "==> Sanity check (expect a 'Radeon 8060S ... (RADV GFX1151)' line)"
/opt/llama.cpp/bin/llama-server --version 2>&1 | head -5 || true
vulkaninfo --summary 2>/dev/null | grep -iE "8060S|GFX1151" || \
  echo "!! Vulkan does not see the 8060S. Check 01-base/strix-halo-kernel.md (Mesa version, video/render groups)."

cat <<'EOF'

Rebuild later with:  bash 02-models/install-llamacpp.sh   (same tag unless LLAMACPP_TAG changes)
Next:                bash 02-models/download-models.sh
EOF
