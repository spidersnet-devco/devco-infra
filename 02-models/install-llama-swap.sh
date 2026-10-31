#!/usr/bin/env bash
# 02-models/install-llama-swap.sh
# Installs the llama-swap binary, the gateway config, and a systemd --user
# service on 127.0.0.1:8080. Validates the config, waits for both role models
# to report READY, then smoke-tests tool calling through each alias.
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${MODEL_GATEWAY_URL%/v1}"

echo "==> Downloading llama-swap (linux amd64)"
# Resolve the latest tag from the release redirect (no GitHub API, no rate limit).
VER="${LLAMA_SWAP_VERSION:-}"
if [[ -z "$VER" ]]; then
  VER="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/mostlygeek/llama-swap/releases/latest | sed -E 's#.*/tag/v?##')"
fi
[[ -n "$VER" ]] || { echo "!! could not resolve the llama-swap version"; exit 1; }
ASSET="llama-swap_${VER}_linux_amd64.tar.gz"      # goreleaser: {{ProjectName}}_{{Version}}_{{Os}}_{{Arch}}
TMP="$(mktemp -d)"
curl -fsSL "https://github.com/mostlygeek/llama-swap/releases/download/v${VER}/${ASSET}" -o "$TMP/llama-swap.tar.gz"
tar -xzf "$TMP/llama-swap.tar.gz" -C "$TMP"
mkdir -p /opt/llama-swap
install -m 0755 "$(find "$TMP" -type f -name 'llama-swap' | head -1)" /opt/llama-swap/llama-swap
/opt/llama-swap/llama-swap -version || true
sed -i '/^llama-swap=/d' /opt/devco/versions.txt 2>/dev/null || true
echo "llama-swap=v$VER ($(date +%F))" >> /opt/devco/versions.txt

echo "==> Config"
if [[ -f /opt/llama-swap/config.yaml ]] && ! cmp -s "$HERE/llama-swap.yaml" /opt/llama-swap/config.yaml; then
  cp /opt/llama-swap/config.yaml "/opt/llama-swap/config.yaml.bak.$(date +%Y%m%d-%H%M%S)"
  echo "    (previous config backed up next to it)"
fi
install -m 0644 "$HERE/llama-swap.yaml" /opt/llama-swap/config.yaml

# Point the macros at the files that actually exist (download-models.sh names them).
pick() {  # pick <dir> <substring>: first .gguf in dir whose name contains substring (drafts/mmproj excluded)
  local f; shopt -s nullglob nocaseglob
  for f in "$1"/*.gguf; do
    case "${f##*/}" in *eagle3*|*mmproj*) continue ;; esac
    [[ "${f##*/}" == *"$2"* ]] && { echo "$f"; break; }
  done
  shopt -u nullglob nocaseglob; return 0
}
GPTOSS="$(pick "$DEVCO_MODELS/gpt-oss-120b" MXFP4)"
QWEN36="$(pick "$DEVCO_MODELS/qwen3.6-35b-a3b" UD-Q4_K_XL)"
[[ -n "$GPTOSS" ]] && sed -i "s#^  \"gptoss_gguf\":.*#  \"gptoss_gguf\": \"$GPTOSS\"#" /opt/llama-swap/config.yaml
[[ -n "$QWEN36" ]] && sed -i "s#^  \"qwen36_gguf\":.*#  \"qwen36_gguf\": \"$QWEN36\"#" /opt/llama-swap/config.yaml
grep -E 'gptoss_gguf|qwen36_gguf' /opt/llama-swap/config.yaml
for f in "$GPTOSS" "$QWEN36"; do
  [[ -s "$f" ]] || { echo "!! model file missing: ${f:-<none found>}. Run 02-models/download-models.sh"; exit 1; }
done

echo "==> Validating config"
/opt/llama-swap/llama-swap -config /opt/llama-swap/config.yaml -validate

echo "==> systemd --user service"
mkdir -p ~/.config/systemd/user
install -m 0644 "$HERE/llama-swap.service" ~/.config/systemd/user/llama-swap.service
systemctl --user daemon-reload
systemctl --user enable --now llama-swap.service
systemctl --user restart llama-swap.service      # pick up a changed config on re-runs
sleep 3
systemctl --user --no-pager status llama-swap.service | head -5

echo "==> Waiting for both models to preload (cold load of 85 GB: several minutes)"
ready() { curl -fsS "$BASE/running" 2>/dev/null | jq -e --arg m "$1" '.running[]? | select(.model==$m and .state=="ready")' >/dev/null 2>&1; }
for _ in $(seq 1 180); do
  ready coder-accurate && ready coder-fast && break
  sleep 5
done
curl -fsS "$BASE/running" | jq -c '.running[]? | {model, state}' || true

echo "==> Smoke test: a chat completion WITH a tool, through each role alias"
TOOLS='[{"type":"function","function":{"name":"get_time","description":"Current time","parameters":{"type":"object","properties":{"tz":{"type":"string"}},"required":["tz"]}}}]'
smoke() {  # smoke <model> <extra-json-fields>
  local out
  out="$(curl -fsS -m 300 "$MODEL_GATEWAY_URL/chat/completions" -H "Content-Type: application/json" -d "{
      \"model\":\"$1\",\"max_tokens\":300,$2
      \"messages\":[{\"role\":\"user\",\"content\":\"What time is it in Tokyo? Use the tool.\"}],
      \"tools\":$TOOLS,\"tool_choice\":\"auto\"}")" || { echo "   $1: request FAILED"; return 1; }
  if echo "$out" | jq -e '.choices[0].message.tool_calls[0].function.name=="get_time"' >/dev/null 2>&1; then
    echo "   $1: tool call OK  ($(echo "$out" | jq -c '.choices[0].message.tool_calls[0].function'))"
  else
    echo "   $1: NO tool call. Reply was: $(echo "$out" | jq -c '.choices[0].message | {content, reasoning_content}' | cut -c1-300)"
    return 1
  fi
}
FAILS=0
smoke coder-fast ""                                  || FAILS=$((FAILS+1))
smoke coder-accurate '"reasoning_effort":"low",'     || FAILS=$((FAILS+1))
(( FAILS == 0 )) || echo "!! $FAILS smoke test(s) failed. Logs: journalctl --user -u llama-swap -n 100 ; $BASE/ui"

cat <<EOF

Gateway is up at $MODEL_GATEWAY_URL
  UI / logs : $BASE/ui
  Running   : $BASE/running
Next: bash 03-paperclip/install-paperclip.sh   (the unattended bootstrap does this for you)
EOF
# exit 3 = llama-swap is up and serving, but a smoke test failed (soft failure)
(( FAILS == 0 )) || exit 3
