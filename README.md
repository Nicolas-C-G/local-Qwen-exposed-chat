# local-Qwen-exposed-chat

This repository contains documentation and deployment helpers for running Qwen AI locally with llama.cpp and optional authenticated remote access.

Local inference was verified on an Ubuntu VM with 8 GB RAM, four vCPUs and no dedicated GPU. Public authenticated access and the automated deployment scripts still require end-to-end testing.

## Installation

On a fresh Ubuntu Server VM, configure SSH using [the manual](docs/IA-Server-Manual.md), then clone this repository as a non-root sudo-capable user.

```bash
git clone -b develop https://github.com/Nicolas-C-G/local-Qwen-exposed-chat.git
cd local-Qwen-exposed-chat
bash scripts/install-llama.sh
bash scripts/download-model.sh
bash scripts/install-service.sh
bash scripts/smoke-test.sh
```

Optional: create persistent swap on a fresh machine with `sudo bash scripts/setup-swap.sh`. Read the manual first.

For remote access, install cloudflared with `sudo bash scripts/install-cloudflared.sh` and follow [Cloudflare setup](infrastructure/cloudflare/README.md). Configure Access before publishing. All domains, identity addresses, tunnel names and tokens are placeholders; set actual values privately in the dashboard. Never commit credentials.

The inference service binds to 127.0.0.1:8080, uses Qwen3 4B Q4_K_M, and defaults to 16,384 context tokens, four threads and one inference slot. Set CONTEXT_SIZE=4096 for initial testing. LLAMA_REF optionally selects a reviewed upstream revision; record the printed revision and model checksum.

Windows: use `scripts/connect-windows.ps1` with your own SSH key path. Browse http://127.0.0.1:8080 while connected.

## Operations

```bash
sudo systemctl status llama-server
sudo journalctl -u llama-server -f
bash scripts/smoke-test.sh
```

Do not publish an unauthenticated inference API. No custom frontend, user quotas or production authentication validation are included.
