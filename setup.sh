#!/usr/bin/env bash
# Qwen3.8-27B + DFlash 2 speculative decoding on Apple Silicon, one command:
#
#   curl -fsSL https://raw.githubusercontent.com/delneg/qwen-dflash/master/setup.sh | bash
#
# Downloads a prebuilt llama-server (llama.cpp fork with DFlash 2, Metal build)
# and writes a start.sh. Models (~20 GB) download on first launch.
# Works on macOS 14+, no OS update needed. Needs a 36 GB+ Mac (48 GB is comfy).
set -euo pipefail

REPO="delneg/qwen-dflash"
DIR="${QWEN_DFLASH_DIR:-$HOME/qwen-dflash}"
ASSET="llama-server-macos-arm64.tar.gz"

if [[ "$(uname -s)/$(uname -m)" != "Darwin/arm64" ]]; then
  echo "This script targets Apple Silicon Macs (got $(uname -s)/$(uname -m))." >&2
  echo "For Windows + NVIDIA, see windows/setup.ps1 in the repo." >&2
  exit 1
fi

echo "==> Installing into $DIR"
mkdir -p "$DIR"
cd "$DIR"

echo "==> Downloading prebuilt llama-server (DFlash 2 build)"
curl -fL --progress-bar -o "$ASSET" \
  "https://github.com/$REPO/releases/latest/download/$ASSET"
tar xzf "$ASSET"
rm "$ASSET"
chmod +x llama-server

cat > start.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# n_max=3 measured fastest on M1 Max (16-18 tok/s, 84% draft acceptance).
# Newer chips: try 5-7. First launch downloads ~20 GB of models to
# ~/.cache/huggingface/hub/ and reuses them afterwards.
exec ./llama-server \
  -hf  ggml-org/Qwen3.8-27B-GGUF:Q4_K_M \
  -hfd incoai/Qwen3.8-27B-DFlash2-GGUF:Q4_K_M \
  --spec-type draft-dflash \
  --spec-draft-n-max 3 \
  --image-min-tokens 1024 \
  -c 8192 -ngl 99 --host 127.0.0.1 --port 8080 "$@"
EOF
chmod +x start.sh

echo
echo "Done. Start the server with:"
echo
echo "    $DIR/start.sh"
echo
echo "then open http://127.0.0.1:8080 for the chat UI"
echo "(OpenAI-compatible API on http://127.0.0.1:8080/v1)."
echo "Ctrl+C stops it. First launch downloads ~20 GB of models."
