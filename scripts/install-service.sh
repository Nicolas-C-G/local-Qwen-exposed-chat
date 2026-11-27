#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "Run as inference user, not root." >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
user="$(id -un)"
ctx="${CONTEXT_SIZE:-16384}"
threads="${THREADS:-4}"
[[ "$user" =~ ^[a-zA-Z0-9_-]+$ && "$HOME" =~ ^/[a-zA-Z0-9_./-]+$ && "$ctx" =~ ^[1-9][0-9]*$ && "$threads" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid configuration." >&2; exit 1; }
[[ -x "$HOME/llama.cpp/build/bin/llama-server" && -f "$HOME/models/Qwen3-4B-Q4_K_M.gguf" ]] || { echo "Install llama.cpp and model first." >&2; exit 1; }
if ! systemctl is-active --quiet llama-server && ss -H -ltn 'sport = :8080' | grep -q .; then
  echo "Port 8080 is occupied; stop the existing process first." >&2
  exit 1
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -e "s|@USER@|$user|g" -e "s|@HOME@|$HOME|g" -e "s|@CONTEXT@|$ctx|g" -e "s|@THREADS@|$threads|g" "$root/infrastructure/systemd/llama-server.service" > "$tmp/llama-server.service"
sudo systemd-analyze verify "$tmp/llama-server.service"
sudo install -m 0644 "$tmp/llama-server.service" /etc/systemd/system/llama-server.service
sudo systemctl daemon-reload
sudo systemctl enable llama-server
sudo systemctl restart llama-server
