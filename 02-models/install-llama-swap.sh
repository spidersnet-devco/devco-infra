#!/usr/bin/env bash
# 02-models/install-llama-swap.sh
# Installs the llama-swap binary, the gateway config, and a systemd --user
# service on 127.0.0.1:8080. Then smoke-tests both role aliases.
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Downloading latest llama-swap (linux amd64)"
API="https://api.github.com/repos/mostlygeek/llama-swap/releases/latest"
ASSET_URL="$(curl -fsSL "$API" | jq -r '.assets[] | select(.name | test("linux_amd64\\.tar\\.gz$")) | .browser_download_url' | head -1)"
[[ -n "$ASSET_URL" ]] || { echo "Could not find a linux_amd64 release asset"; exit 1; }
TMP="$(mktemp -d)"
curl -fsSL "$ASSET_URL" -o "$TMP/llama-swap.tar.gz"
tar -xzf "$TMP/llama-swap.tar.gz" -C "$TMP"
install -m 0755 "$(find "$TMP" -type f -name 'llama-swap' | head -1)" /opt/llama-swap/llama-swap
/opt/llama-swap/llama-swap -version || true

echo "==> Config"
install -m 0644 "$HERE/llama-swap.yaml" /opt/llama-swap/config.yaml

# Fill in the real GGUF paths if download-models.sh produced different names.
GPTOSS="$(ls "$DEVCO_MODELS"/gpt-oss-120b/*-00001-of-*.gguf 2>/dev/null | head -1 || true)"
QWEN="$(ls "$DEVCO_MODELS"/qwen3-coder-30b-a3b/*.gguf 2>/dev/null | head -1 || true)"
[[ -n "$GPTOSS" ]] && sed -i "s#^  \"gptoss_gguf\":.*#  \"gptoss_gguf\": \"$GPTOSS\"#" /opt/llama-swap/config.yaml
[[ -n "$QWEN"   ]] && sed -i "s#^  \"qwen_gguf\":.*#  \"qwen_gguf\":   \"$QWEN\"#" /opt/llama-swap/config.yaml
grep -E 'gptoss_gguf|qwen_gguf' /opt/llama-swap/config.yaml

echo "==> systemd --user service"
mkdir -p ~/.config/systemd/user
install -m 0644 "$HERE/llama-swap.service" ~/.config/systemd/user/llama-swap.service
systemctl --user daemon-reload
systemctl --user enable --now llama-swap.service
sleep 3
systemctl --user --no-pager status llama-swap.service | head -5

echo "==> Waiting for both models to preload (first cold load can take several minutes)"
for i in $(seq 1 120); do
  if curl -fsS "${MODEL_GATEWAY_URL%/v1}/running" 2>/dev/null | grep -q coder-accurate; then break; fi
  sleep 5
done
curl -fsS "${MODEL_GATEWAY_URL%/v1}/running" || true
echo

echo "==> Smoke test: tool calling through the gateway"
for M in coder-fast coder-accurate; do
  echo "--- $M"
  curl -fsS "$MODEL_GATEWAY_URL/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word OK.\"}],\"max_tokens\":20}" \
    | jq -r '.choices[0].message.content'
done

cat <<EOF

Gateway is up at $MODEL_GATEWAY_URL
  UI / logs : ${MODEL_GATEWAY_URL%/v1}/ui
  Running   : ${MODEL_GATEWAY_URL%/v1}/running
Next: bash 03-paperclip/install-paperclip.sh
EOF
