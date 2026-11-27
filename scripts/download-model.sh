#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "Run as the inference user." >&2; exit 1; }
mkdir -p "$HOME/models"
file="$HOME/models/Qwen3-4B-Q4_K_M.gguf"
if [[ ! -f "$file" ]]; then
  wget -c -O "$file.part" 'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf'
  [[ "$(head -c 4 "$file.part")" == GGUF ]] || { echo "Invalid GGUF header" >&2; exit 1; }
  mv "$file.part" "$file"
fi
[[ "$(head -c 4 "$file")" == GGUF ]] || { echo "Invalid GGUF header" >&2; exit 1; }
sha256sum "$file"
