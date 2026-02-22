# Systemd user units

This directory contains systemd **user** units for:

- `*-stack.service` units that manage podman-compose stacks.
- `duplicati-backup.service` + `duplicati-backup.timer` for scheduled backups.
- `llama-server.service` / model-specific llama.cpp services.
- Zoopa on-demand socket activation (`zoopa-ondemand@.socket`).

## Install (symlink + reload)

```bash
mkdir -p ~/.config/systemd/user

ln -s /path/to/podman-compose/systemd/<unit>.service ~/.config/systemd/user/
ln -s /path/to/podman-compose/systemd/<unit>.socket  ~/.config/systemd/user/

systemctl --user daemon-reload
```

## Stack units (`*-stack.service`)

Stack units call `podman-compose up -d` / `down` from the matching stack directory.
The **duplicati** stack is the exception: it runs rootful via sudo while all
other stacks remain rootless.
If a stack uses `.env`, create it from the local `.env.example` before starting:

```bash
cd /path/to/podman-compose/<stack>
cp .env.example .env
```

Enable and manage them as usual:

```bash
systemctl --user enable <stack>-stack.service
systemctl --user start <stack>-stack.service
systemctl --user status <stack>-stack.service
```

## llama.cpp services

The llama.cpp units assume:

- `~/llama.cpp` contains the built `llama-server` binary.
- `~/models` contains the referenced model files.

Adjust paths, ports, and CPU affinity as needed for your host.

## Zoopa on-demand sockets

The Zoopa units provide socket activation that brings a stack up on the first
request and shuts it down after an idle timeout.

1. Create an environment file per stack at:
   `~/.config/zoopa-ondemand/<stack>.env`

   Example:

   ```bash
   ZOOPA_UPSTREAM=127.0.0.1:8080
   ZOOPA_IDLE_TIMEOUT=600   # optional override (seconds)
   # ZOOPA_STACK_UNIT=<stack>-stack.service   # optional override
   ```

2. Enable the directory helper and socket:

   ```bash
   systemctl --user enable --now zoopa-ondemand-dir.service
   systemctl --user enable --now zoopa-ondemand@<stack>.socket
   ```

Nginx (or another reverse proxy) can then connect to
`$XDG_RUNTIME_DIR/ondemand/<stack>.sock`.

## Duplicati backup timer

`duplicati-backup.service` runs the backup script with explicit stack args:

```ini
ExecStart=%h/podman-compose/duplicati/bin/backup cryptpad
```

When you validate additional stack configs, append them as arguments in that
single `ExecStart` line.

Rootful Duplicati requirements:
- `systemd/duplicati-stack.service` uses `sudo /usr/bin/podman-compose`.
- Ensure a tightly-scoped sudoers rule exists for those commands.

Enable schedule:

```bash
systemctl --user daemon-reload
systemctl --user enable --now duplicati-backup.timer
```
