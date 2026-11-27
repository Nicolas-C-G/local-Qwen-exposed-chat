#!/usr/bin/env bash
set -euo pipefail
for i in $(seq 1 60); do
  if curl -fsS --max-time 3 http://127.0.0.1:8080/health | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    curl -fsS --max-time 10 http://127.0.0.1:8080/v1/models
    printf '\nLocal health and models endpoints passed.\n'
    exit 0
  fi
  sleep 2
done
echo "Server not ready; inspect journalctl -u llama-server." >&2
exit 1
