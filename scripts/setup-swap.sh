#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
if [[ -e /swapfile || -L /swapfile ]]; then
  echo "Existing /swapfile; inspect manually. No changes made." >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then
  echo "Existing fstab entry; inspect manually." >&2; exit 1
fi
size="${SWAP_GIB:-10}"
[[ "$size" =~ ^[1-9][0-9]*$ && ${#size} -le 3 ]] || exit 1
avail="$(df -B1 --output=avail / | tail -1)"
(( avail > (size+2)*1024*1024*1024 )) || { echo "Insufficient free disk space." >&2; exit 1; }
umask 077
fallocate -l "${size}G" /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-ai-server.conf
sysctl -p /etc/sysctl.d/99-ai-server.conf
swapon --show
