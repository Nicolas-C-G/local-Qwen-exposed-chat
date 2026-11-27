# IA-Server — Installation and Operations Manual

**Version 1.1 (sanitized public edition) · 27 November 2026**  
**Scope:** Local Qwen3 inference on Ubuntu Server in VirtualBox, secure remote access and Cloudflare authentication.

## 1. Architecture and deployment status

The objective is to host a local LLM and make its existing chat interface available through an authenticated HTTPS website, without paying for a VPS initially.

```text
Internet browser
  -> Cloudflare Access (email PIN / future Google OAuth)
  -> Cloudflare Tunnel (YOUR_TUNNEL_NAME)
  -> cloudflared on Ubuntu VM
  -> llama-server on 127.0.0.1:8080
  -> Qwen3 4B Q4_K_M

Windows administration
  -> SSH 127.0.0.1:2222 (VirtualBox NAT)
  -> Ubuntu SSH port 22
```

| Component | Status at end of conversation |
|---|---|
| Ubuntu Server, SSH, swap | Working / configured |
| llama.cpp, Qwen3 4B | Working; local health endpoint verified |
| 16,384-token context | Running configuration observed |
| systemd service | Configured; user reported completion |
| Windows SSH tunnel | Verified by HTTP health response |
| Cloudflare tunnel `YOUR_TUNNEL_NAME` and chat hostname | Published earlier; cleanup/recreation discussed |
| Cloudflare Access | Login page reached; PIN delivery unresolved |
| Custom TypeScript website, Auth0, SQLite | Planned, not implemented |

**Important:** Public authenticated inference has not yet been verified. After the cleanup discussion, the final state of the published route is not independently confirmed. Do not treat the public deployment as complete.

## 2. Operating system and VirtualBox

Ubuntu Server (minimized) was selected instead of Debian Cloud because it offers a conventional ISO installer and familiar Ubuntu tooling. Debian netinst without a desktop is another suitable option; cloud images are useful for reproducible provisioning with cloud-init but require initial credentials and disk preparation. Docker is optional; it packages dependencies but does not eliminate application memory usage.

Recommended VM settings: 8 GB allocated RAM, 4 vCPUs initially, approximately 60 GB dynamically allocated disk, NAT network, no graphical desktop or 3D acceleration. Install OpenSSH during setup if offered. The exact Ubuntu release was not confirmed; a boot screenshot showed kernel 7.0.0-44-generic.

```bash
sudo apt update
sudo apt upgrade -y
free -h
df -h /
lscpu
nproc
```

Measured idle RAM was 466.7 MiB, later around 504 MiB; usable RAM was about 7.3 GiB and available disk space before swap was 52 GiB. This made local website hosting plausible without a VPS.

### Keyboard and boot troubleshooting

For a Latin American keyboard on the VM console, run `sudo dpkg-reconfigure keyboard-configuration`, choose Generic 105-key PC and Spanish (Latin American). If the menu only shows English variants, edit `/etc/default/keyboard` directly:

```ini
XKBMODEL="pc105"
XKBLAYOUT="latam"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
```

Apply with `sudo setupcon` from the console. No Compose key is necessary. SSH uses the client keyboard layout.

A boot stall showed systemd-fsck-root and RCU warnings. A hard reset restored operation; the underlying cause was not established. Prefer graceful shutdown and back up important data before forced power-off. If it recurs, inspect previous boot logs, test fewer vCPUs, check VirtualBox/kernel compatibility and investigate storage. Never run filesystem repair on a mounted filesystem.

```bash
sudo journalctl -b -1 -p err --no-pager
sudo journalctl -b -p err --no-pager
```

## 3. Secure SSH administration

On Ubuntu:

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo systemctl status ssh
sudo whoami
```

The last command should return `root` for the administrative `ubuntu` account.

VirtualBox > Settings > Network > NAT > Port Forwarding: create TCP rule SSH, host IP `127.0.0.1`, host port `2222`, guest IP blank, guest port `22`. This keeps SSH accessible from the Windows host only.

On Windows PowerShell, generate a key (do not overwrite an existing key):

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\ia-server"
Get-Content "$env:USERPROFILE\.ssh\ia-server.pub" | ssh -p 2222 ubuntu@127.0.0.1 "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
ssh -i "$env:USERPROFILE\.ssh\ia-server" -p 2222 ubuntu@127.0.0.1
```

Verify the server fingerprint using `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the VM. Substitute your local key path if different. Keep the private key outside the repository and protect it with a passphrase.

Optional Windows SSH config (`%USERPROFILE%\.ssh\config`):

```ssh-config
Host ia-server
    HostName 127.0.0.1
    Port 2222
    User ubuntu
    IdentityFile ~/.ssh/ia-server
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

### Disable SSH password and root login

First test key-only login in a second session and confirm `sudo whoami` works. Create `/etc/ssh/sshd_config.d/00-security.conf`:

```ini
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
```

```bash
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E 'passwordauthentication|pubkeyauthentication|permitrootlogin|kbdinteractiveauthentication'
```

Keep the existing session open while testing a new connection. Password login via the VirtualBox console and normal sudo access remain available for the `ubuntu` account, assuming its password is valid. SSH restrictions do not lock the local account.

## 4. Swap and memory management

The VM initially had no swap. A 10 GiB swap file was selected for experimentation. Check that no swap file already exists before creating one; do not run these creation commands again against an active swap file.

```bash
free -h
swapon --show
df -h /
sudo fallocate -l 10G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

Add `/swapfile none swap sw 0 0` to `/etc/fstab` once (avoid duplicate entries). Set low swappiness:

```bash
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-ai-server.conf
sudo sysctl --system
free -h
swapon --show
cat /proc/sys/vm/swappiness
grep swap /etc/fstab
```

The observed `swapon --show` reported 10G and zero used; `free -h` displayed 9Gi due to formatting/usable capacity. Swap is disk-backed emergency capacity, not equivalent to RAM. Larger models may page continuously and become very slow. Model weights mapped from disk may be reclaimed and reread independently of swap.

## 5. Install llama.cpp and Qwen3

Compile natively on Ubuntu for CPU inference. No GPU or Docker required.

```bash
sudo apt install -y git cmake build-essential libcurl4-openssl-dev curl wget htop
cd ~
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_CUDA=OFF
cmake --build build --config Release -j 2
./build/bin/llama-server --version
mkdir -p ~/models
cd ~/models
wget -c https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf
ls -lh
```

The model selected is Qwen3 4B Q4_K_M: a general-purpose text assistant for conversation, reasoning, coding and tool calling. It is not a vision model. Qwen3-VL and Qwen2.5-Coder were discussed as future alternatives; Kimi's larger MoE weights are generally less suited to this VM. Active parameter count is not the total memory requirement.

Start with a 4096-token context if testing a fresh installation. The following command is the later observed working configuration:

```bash
cd ~/llama.cpp
./build/bin/llama-server \
  --model /home/ubuntu/models/Qwen3-4B-Q4_K_M.gguf \
  --alias qwen3-4b --host 127.0.0.1 --port 8080 \
  --ctx-size 16384 --threads 4 --parallel 1 \
  --batch-size 256 --ubatch-size 128 --n-gpu-layers 0 --jinja
```

Keep the server bound to loopback. `--jinja` enables template processing relevant to tool calling, but actual tools and authorization still require application-side implementation and testing.

## 6. Test inference and Windows access

From Ubuntu (in a second terminal):

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-4b","messages":[{"role":"user","content":"Explain REST APIs briefly. /no_think"}],"max_tokens":256,"stream":false}'
```

Health response observed: `{"status":"ok"}`.

From Windows, open a dedicated PowerShell window (substitute the real private key path):

```powershell
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -L 127.0.0.1:8080:127.0.0.1:8080 -i "$env:USERPROFILE\.ssh\ia-server" -p 2222 ubuntu@127.0.0.1
```

The terminal stays open without a shell; this is normal. In another window run `curl.exe http://127.0.0.1:8080/health` and open `http://localhost:8080` in the browser. The Windows health check succeeded and the user confirmed the chat was ready.

PowerShell JSON request:

```powershell
$body = @{
  model = 'qwen3-4b'
  messages = @(@{role='user'; content='Write Hello World in TypeScript. /no_think'})
  max_tokens = 512
  stream = $false
} | ConvertTo-Json -Depth 10
$body | curl.exe -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' --data-binary '@-'
```

Troubleshooting: `Identity file not accessible` means the key path is wrong; `ssh -v -N ...` provides diagnostic output. If port 8080 is in use locally, forward 8081 to guest 8080 instead. A missing `known_hosts2` file is not a failure. A returned prompt indicates the tunnel ended; Ctrl+C intentionally closes it.

## 7. Context window and CPU performance

The context includes system instructions, input, conversation history and generated tokens. Increasing capacity increases KV-cache memory; processing long prompts also increases CPU work. With one inference slot, the configured context is available to that slot.

| Context tokens | F16 KV cache (estimated) | Q8_0 KV cache (estimated) |
|---|---:|---:|
| 4,096 | 576 MiB | 306 MiB |
| 8,192 | 1,152 MiB | 612 MiB |
| 16,384 | 2,304 MiB | 1,224 MiB |
| 32,768 | 4,608 MiB | 2,448 MiB |

These are theoretical estimates for Qwen3 4B, excluding weights and buffers. The observed 16K command did not enable KV-cache quantization. Optional future experiment: `--cache-type-k q8_0 --cache-type-v q8_0 --flash-attn on` (check build support and quality/performance). Context beyond 32K requires appropriate model-specific extension settings and validation; not recommended initially.

The htop screenshot showed all four vCPUs at 100%, memory bar 4.24/7.25 GiB, swap 20 KiB/10 GiB. Resident memory included shared/mapped pages; do not sum repeated thread rows. CPU saturation suggests compute or memory bandwidth constraints, not proof that more cores will improve throughput.

```bash
free -h
vmstat 1
htop
```

On Windows, inspect host CPU before increasing VM allocation:

```powershell
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors
```

Stop the inference service before benchmarking to avoid loading the model twice. Test thread counts supported by the VM:

```bash
sudo systemctl stop llama-server
cd ~/llama.cpp
./build/bin/llama-bench -m ~/models/Qwen3-4B-Q4_K_M.gguf -t 2,4 -p 512 -n 128 -r 3
sudo systemctl start llama-server
```

Record prompt processing and generation tokens/sec, RAM available and swap I/O. No benchmark results were provided in the conversation.

## 8. Make inference persistent with systemd

Stop the manual process first. Use `kill -TERM <PID>` only after confirming the current process ID. Find the current process and stop it if necessary.

```bash
pgrep -a llama-server
ss -tlnp | grep ':8080'
```

Create `/etc/systemd/system/llama-server.service` with the working parameters:

```ini
[Unit]
Description=Qwen3 AI Inference Server
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/llama.cpp
ExecStart=/home/ubuntu/llama.cpp/build/bin/llama-server \
    --model /home/ubuntu/models/Qwen3-4B-Q4_K_M.gguf \
    --alias qwen3-4b --host 127.0.0.1 --port 8080 \
    --ctx-size 16384 --threads 4 --parallel 1 \
    --batch-size 256 --ubatch-size 128 --n-gpu-layers 0 --jinja
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemd-analyze verify /etc/systemd/system/llama-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now llama-server
systemctl is-enabled llama-server
systemctl is-active llama-server
curl http://127.0.0.1:8080/health
sudo journalctl -u llama-server -f
```

The verification output included unrelated CPUAccounting deprecation warnings from xfs_scrub units. The user reported completing service setup. Ctrl+C exits journal viewing, not the service. Use `sudo systemctl restart llama-server` after changing configuration (run daemon-reload first), and `sudo systemctl stop llama-server` to stop it.

## 9. Cloudflare Access and Tunnel

The chosen approach exposes the existing chat interface without a separate web server or external VPS. The example domain is `chat.example.com`, tunnel `YOUR_TUNNEL_NAME`. Replace these placeholders with your own private configuration. Configure Access before publishing. During troubleshooting, remove the public route before deleting or disabling the Access application; check that no alternate hostname exposes the API.

### Access application and identity provider

1. Dashboard > Access controls > Applications > Add application > Self-hosted. Use name `IA-Server` (earlier name `chat`), hostname `chat.example.com`, empty path, session duration 24 hours (initial choice).
2. Add an Allow policy directly to the application. Include > Emails > an explicitly authorized address, e.g. `user@example.com` (replace before saving). No Require or Exclude rules for initial testing. Never use Everyone or Bypass as a workaround.
3. Under Integrations > Identity providers, confirm One-time PIN exists. In the application editor, scroll below policies to Authentication > Identity. Disable Accept all available identity providers, select One-time PIN, leave instant authentication and Cloudflare One Client off initially. Save. If this section is absent during creation, save and reopen the application. Dashboard labels can change.
4. Confirm the policy is attached to the intended application and hostname. No manual user registration is needed for OTP.

### Install cloudflared on Ubuntu

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
sudo apt install -y cloudflared
cloudflared --version
```

In Networking > Tunnels, create or select `YOUR_TUNNEL_NAME`, choose Cloudflared, and run the dashboard-provided `sudo cloudflared service install YOUR_TUNNEL_TOKEN` once if not already installed. Never commit the real token. Verify `systemctl is-active cloudflared` and tunnel health.

Inside the specific tunnel, add a **Published application** route (not the general private Routes screen). Use subdomain `chat`, domain `example.com`, empty path, HTTP origin `127.0.0.1:8080`. Enable Protect with Access in origin settings and configure the correct Access application audience/team if requested. Verify it matches the Access application before publishing.

## 10. Authentication troubleshooting and launch tests

The login screen appeared, but no PIN arrived. Initially the policy was unattached; attaching it did not resolve delivery. Later screenshots showed one Allow rule for the correct email, attached to the self-hosted `chat` application, and One-time PIN registered as the sole identity provider. The policy tester returned `access.api.error.invalid_user_id` and evaluated zero policies: it had no previously established user identity. This is not evidence of policy denial.

Next actions:

- Finish recreating the Access application and verify its Authentication > Identity configuration (current stopping point).
- Check Gmail spam and search `in:anywhere from:noreply@notify.cloudflare.com` or `in:anywhere cloudflare newer_than:1d`.
- Test a second email you control, explicitly included in the Allow policy. If delivery fails for only one address, investigate email suppression with Cloudflare Support. No definitive root cause has been established.
- If OTP still fails, consider Google OAuth. Add Google in Integrations > Identity providers; create a Google Cloud OAuth web client with an external audience and test user if needed. Use the team origin `https://YOUR_TEAM.cloudflareaccess.com` and redirect `https://YOUR_TEAM.cloudflareaccess.com/cdn-cgi/access/callback` (verify these against the actual dashboard). Enter Client ID and secret into Cloudflare, test provider, enable it for the app and keep the same restrictive email policy. This was proposed, not implemented.

### Acceptance checklist

- Both `systemctl is-active cloudflared` and `systemctl is-active llama-server` return active.
- Private browser visits `https://chat.example.com` and sees authentication.
- Authorized user signs in and completes a chat request, including from mobile data.
- Unauthorized email cannot enter; unauthenticated API requests are denied or redirected, never returning inference data.
- Protect with Access is enabled; local inference remains loopback-only; no unprotected alternate routes exist.
- Reboot VM and verify services return; no secrets in GitHub.

```powershell
curl.exe -i https://chat.example.com/health
curl.exe -i https://chat.example.com/v1/models
```

Do not follow redirects for this initial check. A 200 response containing actual model/health data without authentication is a failure. Access protects reachability, but does not provide per-user quotas, isolated server-side history or fine-grained inference API permissions. Limit access to trusted users and verify which administrative endpoints are available before expanding access.

## 11. Future development and repository plan

A lightweight custom React + TypeScript interface, Fastify backend, SQLite database and Auth0 were discussed, but none has been implemented. Compile frontend assets on the development computer if resources are constrained. Keep the inference API private; backend should enforce authorization, input/output limits, concurrency, timeouts, rate limits and tool permissions. Add streaming responses and conversation persistence after the basic API works.

```text
IA-Server/
  frontend/
  backend/
  infrastructure/systemd/llama-server.service
  infrastructure/cloudflare/
  scripts/install-llama.sh
  scripts/download-model.sh
  scripts/deploy.sh
  docs/
  .gitignore
  README.md
```

Suggested initial endpoints: GET /api/health, GET /api/models, POST /api/chat. A separate VPS is an option later (no GPU required); it can host the website and database while inference stays local through a protected tunnel or private VPN. Local-only hosting avoids VPS costs but depends on the host computer, VM and internet connection remaining online.

## 12. Reference links

These are documentation links discussed during the conversation; commands and dashboard labels should be checked against the installed versions before deploying again.

- Ubuntu Server: https://ubuntu.com/download/server
- Debian netinst: https://www.debian.org/distrib/netinst
- Debian cloud images: https://cloud.debian.org/images/cloud/trixie/latest/
- llama.cpp: https://github.com/ggml-org/llama.cpp
- Qwen3 GGUF: https://huggingface.co/Qwen/Qwen3-4B-GGUF
- Cloudflare Tunnel: https://developers.cloudflare.com/tunnel/get-started/
- Cloudflare OTP: https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/one-time-pin/
- Cloudflare Google: https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/google/
- Cloudflare Access troubleshooting: https://developers.cloudflare.com/cloudflare-one/troubleshooting/access/

**Source and limitations:** This manual consolidates the conversation through 27 November 2026. It distinguishes observed output, user-reported completion, suggested configurations and unresolved work. Commands are consolidated for reproducibility and include explicit safety precautions; they have not been rerun on the VM. No private keys, passwords, tunnel tokens or actual email address are included.