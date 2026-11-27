#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "Run as a non-root sudo-capable user." >&2; exit 1; }
sudo apt-get update
sudo apt-get install -y git cmake build-essential libcurl4-openssl-dev curl wget htop
dir="$HOME/llama.cpp"
if [[ ! -d "$dir/.git" ]]; then
  [[ ! -e "$dir" ]] || { echo "Unexpected existing path: $dir" >&2; exit 1; }
  git clone https://github.com/ggml-org/llama.cpp.git "$dir"
fi
cd "$dir"
if [[ -n "${LLAMA_REF:-}" ]]; then
  git fetch origin
  git checkout --detach "$LLAMA_REF"
fi
git rev-parse HEAD
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_CUDA=OFF
cmake --build build --config Release -j "${BUILD_JOBS:-2}"
./build/bin/llama-server --version
