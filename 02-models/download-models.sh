#!/usr/bin/env bash
# 02-models/download-models.sh
# Downloads the two role models into $DEVCO_MODELS (~86 GB total).
#
#   coder-accurate  gpt-oss-120b, native MXFP4 GGUF, ONE file   63.4 GB
#   coder-fast      Qwen3.6-35B-A3B, Unsloth UD-Q4_K_XL          22.4 GB
#
# Optional extras (each is a separate flag; none is needed for Phase 1):
#   --extra eagle3        EAGLE-3 draft head for gpt-oss speculative decoding  0.85 GB
#   --extra qwen36-q8     Qwen3.6-35B-A3B UD-Q8_K_XL (A/B for the accurate lane) 38.5 GB
#   --extra qwen3-coder   Qwen3-Coder-30B-A3B-Instruct Q4_K_M (previous fast lane) 18.6 GB
#
# Filenames verified against the Hugging Face trees on 2026-10-31. Swap models
# later by changing a repo/file here and the matching macro in llama-swap.yaml;
# nothing else in the company changes.
set -euo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.local/bin:$PATH"     # pipx puts `hf` here

EXTRAS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extra) EXTRAS+=("${2:?--extra needs a name}"); shift 2 ;;
    *) echo "usage: download-models.sh [--extra eagle3|qwen36-q8|qwen3-coder]..."; exit 2 ;;
  esac
done

command -v hf >/dev/null 2>&1 || { echo "!! 'hf' not found. Run: pipx install huggingface_hub && pipx ensurepath"; exit 1; }

GPTOSS_DIR="$DEVCO_MODELS/gpt-oss-120b"
QWEN36_DIR="$DEVCO_MODELS/qwen3.6-35b-a3b"
QWEN3C_DIR="$DEVCO_MODELS/qwen3-coder-30b-a3b"
mkdir -p "$GPTOSS_DIR" "$QWEN36_DIR"

# hf download <repo> <file> --local-dir <dir>   (resumes partial downloads)
fetch() {  # fetch <repo> <file> <dir> <label>
  if [[ -s "$3/$2" ]]; then echo "==> $4: already present ($3/$2)"; return 0; fi
  echo "==> $4"
  hf download "$1" "$2" --local-dir "$3"
}

fetch ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-MXFP4.gguf "$GPTOSS_DIR" \
      "gpt-oss-120b MXFP4 (63.4 GB; this is the long one)"
fetch unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf "$QWEN36_DIR" \
      "Qwen3.6-35B-A3B UD-Q4_K_XL (22.4 GB)"

for x in "${EXTRAS[@]}"; do
  case "$x" in
    eagle3)     fetch ggml-org/gpt-oss-120b-GGUF eagle3-gpt-oss-120b-Q8_0.gguf "$GPTOSS_DIR" "EAGLE-3 draft for gpt-oss (0.85 GB)" ;;
    qwen36-q8)   fetch unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf "$QWEN36_DIR" "Qwen3.6-35B-A3B UD-Q8_K_XL (38.5 GB)" ;;
    qwen3-coder) mkdir -p "$QWEN3C_DIR"
                 fetch unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf "$QWEN3C_DIR" "Qwen3-Coder-30B-A3B Q4_K_M (18.6 GB)" ;;
    *) echo "!! unknown extra: $x"; exit 2 ;;
  esac
done

echo
echo "==> Files:"
ls -lh "$GPTOSS_DIR"/*.gguf "$QWEN36_DIR"/*.gguf 2>/dev/null || true
[[ -d "$QWEN3C_DIR" ]] && ls -lh "$QWEN3C_DIR"/*.gguf 2>/dev/null || true

# Sanity: the two files llama-swap.yaml points at must exist and be the right size.
chk() { local f="$1" min="$2"; local sz; sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
        if (( sz < min )); then echo "!! $f is missing or truncated ($sz bytes); re-run this script"; return 1; fi; }
chk "$GPTOSS_DIR/gpt-oss-120b-MXFP4.gguf"            60000000000
chk "$QWEN36_DIR/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"    21000000000

cat <<EOF

Paths used by 02-models/llama-swap.yaml (install-llama-swap.sh fills them in):
  gptoss_gguf: $GPTOSS_DIR/gpt-oss-120b-MXFP4.gguf
  qwen36_gguf: $QWEN36_DIR/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
EOF
