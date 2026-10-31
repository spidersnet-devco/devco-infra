#!/usr/bin/env bash
# 02-models/download-models.sh
# Downloads the two role models into $DEVCO_MODELS.
#
#   coder-accurate  gpt-oss-120b, native MXFP4 GGUF (~61 GB, 3 shards)
#   coder-fast      Qwen3-Coder-30B-A3B-Instruct, Q4_K_M (~18 GB)
#
# Swap models later by changing the repo/pattern below and the matching
# path in llama-swap.yaml — nothing else in the company changes.
set -euo pipefail
source /opt/devco/devco.env

HF="hf"; command -v hf >/dev/null 2>&1 || HF="huggingface-cli"

mkdir -p "$DEVCO_MODELS/gpt-oss-120b" "$DEVCO_MODELS/qwen3-coder-30b-a3b"

echo "==> gpt-oss-120b (ggml-org, MXFP4). Grab a coffee: ~61 GB."
$HF download ggml-org/gpt-oss-120b-GGUF \
  --include "gpt-oss-120b-mxfp4-*.gguf" \
  --local-dir "$DEVCO_MODELS/gpt-oss-120b"

echo "==> Qwen3-Coder-30B-A3B-Instruct (unsloth, Q4_K_M)"
$HF download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
  --include "*Q4_K_M*.gguf" \
  --local-dir "$DEVCO_MODELS/qwen3-coder-30b-a3b"

echo
echo "==> Files:"
ls -lh "$DEVCO_MODELS"/gpt-oss-120b/*.gguf "$DEVCO_MODELS"/qwen3-coder-30b-a3b/*.gguf

# llama.cpp loads a split model from its first shard; record the paths llama-swap uses.
GPTOSS="$(ls "$DEVCO_MODELS"/gpt-oss-120b/*-00001-of-*.gguf 2>/dev/null | head -1 || true)"
QWEN="$(ls "$DEVCO_MODELS"/qwen3-coder-30b-a3b/*.gguf 2>/dev/null | head -1 || true)"
cat <<EOF

Set these in 02-models/llama-swap.yaml (macros section) if they differ:
  gptoss_gguf: ${GPTOSS:-<not found>}
  qwen_gguf:   ${QWEN:-<not found>}
EOF
