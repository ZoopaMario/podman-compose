# Podman Stacks

Rootless `podman-compose` stacks managed by systemd user services.

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

Each unit calls `podman-compose up -d` / `down` in the corresponding stack directory and uses `RemainAfterExit=yes` so systemd can track “stack active” state.

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
