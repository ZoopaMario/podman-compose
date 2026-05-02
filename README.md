# Podman Stacks

Rootless `podman-compose` stacks managed by systemd user services.
Exception: the `duplicati` stack runs **rootful** via sudo; all other stacks remain rootless.

## Prerequisites

- Podman + podman-compose installed for the unprivileged user.
- Persistent data directories (e.g. via bind mounts) with correct ownership.
- Rootless containers must not run directly on NFS for container storage (only for bind-mounted volumes).

### User lingering

Enable user lingering so systemd user services continue running after logout:

```bash
sudo loginctl enable-linger <user>
````

## Layout

```text
podman-compose/
├── nextcloud/
│   ├── docker-compose.yml
│   ├── .env          # not tracked in git
│   └── .env.example  # template, safe to commit
├── nginx/
│   └── docker-compose.yml
├── pihole/
│   └── docker-compose.yml
├── [...]
│   └── [...]
└── systemd/
    ├── nextcloud-stack.service
    ├── nginx-stack.service
    ├── pihole-stack.service
    └── [...]
```

`.env` files contain secrets and must **not** be committed. Use `.env.example` as a documented template only.

## Systemd user services

Systemd services live in `systemd/` inside the repo and are symlinked into the user systemd directory:

```bash
mkdir -p ~/.config/systemd/user

ln -s /path/to/podman-compose/systemd/nextcloud-stack.service ~/.config/systemd/user/
ln -s /path/to/podman-compose/systemd/nginx-stack.service     ~/.config/systemd/user/
ln -s /path/to/podman-compose/systemd/pihole-stack.service    ~/.config/systemd/user/
[...]

systemctl --user daemon-reload
```

Each unit calls `podman-compose up -d` / `down` in the corresponding stack directory and uses `RemainAfterExit=yes` so systemd can track “stack active” state. `duplicati` is the rootful exception and uses `sudo /usr/bin/podman-compose`.

### Managing stacks

```bash
# enable stack at boot (user systemd)
systemctl --user enable <stack>-stack.service

# start / stop / restart stack
systemctl --user start    <stack>-stack.service
systemctl --user stop     <stack>-stack.service
systemctl --user restart  <stack>-stack.service

# status
systemctl --user status   <stack>-stack.service
```

Replace `<stack>` with `nextcloud`, `nginx`, `pihole`, etc.

## Logs

From a stack directory:

```bash
cd /path/to/podman-compose/<stack>

# combined logs for all services in the stack
podman-compose logs

# follow logs
podman-compose logs -f

# specific service
podman-compose logs -f <service-name>
```

## LLM Setup (Local SBC)

This repo also manages the local llama.cpp-based LLM serving path used by Open WebUI/LiteLLM.

- Service unit (repo): `systemd/llama-server.service`
- Active preset file on host: `~/.config/llama/models.ini`
- Current serving mode: single `llama-server` with `--models-dir` + per-model presets, single API port `8765`
- Open WebUI chunk streaming tuning: `open-webui/docker-compose.yml` (`CHAT_RESPONSE_STREAM_DELTA_CHUNK_SIZE`)

### Current tuned profile

Applied tuning focuses on balanced low warm-latency + stable throughput:

- `mmap = 1`
- `fit = on` (`fit-target = 768`)
- `ubatch-size = 256`
- `cache-type-k = q8_0`
- `cache-type-v = q8_0`
- `flash-attn = on`
- `n-gpu-layers = 999` (Vulkan)
- `sleep-idle-seconds = 900`
- router-level/model-level parallelism increased for multi-user load

### Benchmark artifacts

Primary benchmark script:

- `scripts/benchmark_llm_stack.sh`

*(Note: Raw benchmark results like `.txt` and `.tsv` files are saved locally to `benchmarks/` but are not tracked in git.)*

Build/update runbook for `llama.cpp` (including service restart and validation):

- `benchmarks/qwen_tuning/llama_cpp_build_runbook.md`

### Operational notes

- `mmap = 0` was tested and rejected in this dynamic multi-model setup due to long/stuck model loading.
- `fit = off` and KV cache `q4_0` were tested and rejected (no net benefit vs baseline).
- If throughput/latency degrades, rerun benchmark script first before changing quantization or backend flags.
