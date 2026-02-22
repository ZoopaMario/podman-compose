# Duplicati Per-Stack Backup Orchestrator

Per-stack backup orchestration for **rootful Duplicati only** (via sudo) with
rootless Podman stacks managed by `systemd --user`.
Each stack has its own config (`stacks/<stack>.sh`) and one or more Duplicati jobs.

## Concept

For each selected stack, `bin/backup` does:
1. Optionally freeze Zoopa on-demand socket activation.
2. Stop the stack unit (for example `nextcloud-stack.service`).
3. Wait until containers with label `io.podman.compose.project=<project>` are stopped.
4. Trigger configured Duplicati job(s).
5. Wait until Duplicati reports `Active task: None|Empty` (not just `Server state: Running`).
6. Restore stack state based on `RESTORE_POLICY`.
7. Optionally restore on-demand socket state.
8. Run optional verification hook(s), write logs.

Safety properties:
- Lock file prevents concurrent backup runs.
- Cleanup trap restores service/socket state after failures (best-effort).
- Default restore behavior keeps previously-stopped stacks stopped.

## Layout

```text
duplicati/
├─ bin/backup
├─ stacks/
│  ├─ cryptpad.sh
│  └─ nextcloud.sh
├─ logs/
├─ docker-compose.yml
└─ .env.example
```

## Requirements

- Rootless Podman stacks managed via `systemd --user`.
- Rootful Duplicati container (default name: `duplicati`) started via sudo.
- Sudoers rule allowing `podman-compose up/down` and `podman ps/exec` for Duplicati only.
- Stacks managed via `systemd --user` units.
- Podman compose labels present: `io.podman.compose.project=<stack>`.
- `/mnt/backup` accessible (autofs/NFS is fine; script triggers it).

## Usage

```bash
~/podman-compose/duplicati/bin/backup list
~/podman-compose/duplicati/bin/backup all
~/podman-compose/duplicati/bin/backup cryptpad nextcloud
~/podman-compose/duplicati/bin/backup cryptpad-stack.service
```

## Environment Variables

- `DUPLICATI_CONTAINER` (default `duplicati`)
- `DUPLICATI_RUN_TIMEOUT` (default `25`) timeout for `duplicati-server-util run` enqueue call
- `DUPLICATI_WAIT_TIMEOUT` (default `21600`) max wait for backup completion
- `PODMAN_CMD` (default `sudo -n podman`) override podman invocation used for Duplicati only
- `PODMAN_STACK_CMD` (default `podman`) podman invocation used to check rootless stack containers

Example:
```bash
DUPLICATI_WAIT_TIMEOUT=28800 ~/podman-compose/duplicati/bin/backup nextcloud
```

Rootless override example (testing only):
```bash
PODMAN_CMD=podman ~/podman-compose/duplicati/bin/backup nextcloud
```

## Add a New Stack Backup Configuration

### 1) Create/verify Duplicati jobs first

- Create one or more jobs in Duplicati for that stack.
- Use stable job names (or IDs) and set Duplicati schedule to manual/off if this orchestrator is the scheduler.
- Validate each job from Duplicati UI or:
  - `sudo podman exec duplicati duplicati-server-util list-backups`

### 2) Create `stacks/<stack>.sh`

Use this minimal template:

```bash
STACK_NAME="immich"
UNIT="immich-stack.service"
PROJECT_LABEL="immich"

DUPLICATI_JOBS=(
  "Immich -> Remote"
)

STOP_TIMEOUT=180
START_TIMEOUT=180
RESTORE_POLICY="previous"  # previous|always

# Optional for Zoopa on-demand stacks:
# FREEZE_ONDEMAND="yes"
# ONDEMAND_SOCKET="zoopa-ondemand@immich.socket"
# ONDEMAND_SERVICE="zoopa-ondemand@immich.service"

# Optional hooks:
# stack_pre_stop() { :; }
# stack_post_stop() { :; }
# stack_pre_backup() { :; }
# stack_post_backup() { :; }
# stack_pre_start() { :; }
# stack_post_start() { :; }
# stack_verify() { :; }
```

Rules:
- `UNIT` must be the exact systemd user unit name.
- `PROJECT_LABEL` must match `io.podman.compose.project` label used by that stack.
- `DUPLICATI_JOBS` must not be empty.
- Prefer `RESTORE_POLICY="previous"` for on-demand/usually-idle stacks.

### 3) Validate unit and label mapping

```bash
systemctl --user status immich-stack.service --no-pager
podman ps --format '{{.Names}} {{.Labels}}' | grep io.podman.compose.project=immich
```

### 4) Dry run one stack and inspect logs

```bash
~/podman-compose/duplicati/bin/backup immich
tail -n 100 ~/podman-compose/duplicati/logs/backup-immich-$(date +%F).log
```

### 5) Add to scheduled runs

If using `backup all`, new stack files are picked up automatically by `backup list/all`.

## Hooks

Optional hook functions in each stack file:
- `stack_pre_stop`
- `stack_post_stop`
- `stack_pre_backup`
- `stack_post_backup`
- `stack_pre_start`
- `stack_post_start`
- `stack_verify`

Use hooks for stack-specific consistency work, for example Nextcloud maintenance mode in `stacks/nextcloud.sh`.

## Logging

Per-stack append-only log path:
`~/podman-compose/duplicati/logs/backup-<stack>-YYYY-MM-DD.log`

## systemd Timer (Recommended)

`~/.config/systemd/user/duplicati-backup.service`:
```ini
[Unit]
Description=Duplicati per-stack backups
Wants=podman.socket
After=podman.socket

[Service]
Type=oneshot
ExecStart=%h/podman-compose/duplicati/bin/backup cryptpad
```

`~/.config/systemd/user/duplicati-backup.timer`:
```ini
[Unit]
Description=Nightly Duplicati per-stack backups

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
systemctl --user daemon-reload
systemctl --user enable --now duplicati-backup.timer
```

To add more stacks later, append them to `ExecStart` after manual validation,
for example: `.../bin/backup cryptpad nextcloud`.

## Troubleshooting

- Backup appears stuck:
  - `sudo podman exec duplicati duplicati-server-util status`
  - parser logic lives in `bin/backup` functions `active_task_value`, `status_is_idle`, `status_has_active_task`.
- On-demand app auto-starts during backup:
  - ensure `FREEZE_ONDEMAND="yes"` and valid `ONDEMAND_SOCKET`.
- Stack start/stop does not affect containers:
  - verify `UNIT` and `PROJECT_LABEL` correctness.

## Operational Notes

- Keep Duplicati state DB on local disk (avoid sqlite on NFS).
- Do not run parallel schedulers for the same jobs.
- Treat logs as operational data; they may contain backup names, container names, and timing details.
