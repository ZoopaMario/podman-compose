# Duplicati Per-Stack Backup Orchestrator (rootless Podman + systemd --user)

This directory contains a lightweight backup orchestration layer for **koopa-crypt**.

It is designed for a **rootless Podman** environment where application stacks are managed as **systemd user services** (`*-stack.service`) and actual backup jobs are executed by **Duplicati** inside a container.

The key goals are:

- **Minimal downtime**: each stack is stopped only for the duration of *its own* backup job(s).
- **Safe**: automatic restore of state even if a backup fails mid-run.
- **Maintainable**: one config file per stack, with simple hook functions for stack-specific actions.
- **Works with Duplicati quirks**: we enqueue jobs with a short timeout and then wait for completion by polling `duplicati-server-util status`.

---

## Layout

```

~/podman-compose/duplicati/
├─ bin/
│  └─ backup                # main entry point (run manually or from timer)
├─ stacks/
│  ├─ _template.sh          # template for new stack config
│  ├─ cryptpad.sh           # example on-demand stack config (freezes zoopa socket)
│  └─ nextcloud.sh          # example stack config with maintenance hooks
└─ logs/
└─ backup-<stack>-YYYY-MM-DD.log

```

---

## How it works (high level)

For each stack (e.g. `cryptpad`):

1. (Optional) **Freeze on-demand activation** (Zoopa socket) so the stack cannot be auto-started mid-backup.
2. Stop the stack’s systemd user service (default `cryptpad-stack.service`).
3. Wait until containers with label `io.podman.compose.project=cryptpad` are stopped (best-effort).
4. Trigger one or more configured Duplicati job(s) via:

```

podman exec duplicati duplicati-server-util run "<job name>"

```

5. Wait for the backup to finish by polling:

```

podman exec duplicati duplicati-server-util status

````

It considers the backup complete when:
- `Active task: None` (or `Active task: Empty`)

**Important**: `Server state: Running` does *not* mean a backup is running.

6. Restore the stack according to **RESTORE_POLICY**:
   - `previous` (default): only start the unit again if it was active before backup
   - `always`: always start the unit after backup

7. (Optional) Un-freeze on-demand activation by restoring the Zoopa socket state.
8. Run optional stack-specific verify steps.
9. Write logs to `logs/backup-<stack>-YYYY-MM-DD.log`.

A lockfile prevents concurrent runs (timer + manual).

---

## Requirements / Assumptions

- Rootless Podman is used.
- Duplicati container is running and named `duplicati` (or override with env var).
- Stacks are managed as systemd user units like `cryptpad-stack.service`.
- Your containers are labeled by podman-compose with:
  - `io.podman.compose.project=<stack>`
- `/mnt/backup` is accessible (autofs/NFS). The script triggers autofs by touching the directory.

---

## Usage

### List available stack configs

```bash
~/podman-compose/duplicati/bin/backup list
````

### Back up one stack now

```bash
~/podman-compose/duplicati/bin/backup cryptpad
```

### Back up multiple stacks now

```bash
~/podman-compose/duplicati/bin/backup cryptpad nextcloud vaultwarden
```

### Back up everything (sequentially, per stack)

```bash
~/podman-compose/duplicati/bin/backup all
```

### Accept unit names too

These are normalized:

```bash
~/podman-compose/duplicati/bin/backup cryptpad-stack.service
```

---

## Environment variables

The main script supports these variables:

* `DUPLICATI_CONTAINER`
  Name of the Duplicati container. Default: `duplicati`

* `DUPLICATI_RUN_TIMEOUT`
  Seconds to allow `duplicati-server-util run` to block. Default: `25`
  Why: sometimes `run` can hang; we only need it to enqueue, then we poll status.

* `DUPLICATI_WAIT_TIMEOUT`
  Max seconds to wait for backup completion. Default: `21600` (6h)

Example:

```bash
DUPLICATI_WAIT_TIMEOUT=28800 ~/podman-compose/duplicati/bin/backup immich
```

---

## Per-stack configuration files

Each stack has a file:

```
~/podman-compose/duplicati/stacks/<stack>.sh
```

### Required variables

* `STACK_NAME`
  Human-friendly name (usually same as file name)

* `UNIT`
  systemd user unit to stop/start (e.g. `cryptpad-stack.service`)

* `PROJECT_LABEL`
  podman-compose project label used for container detection (usually same as stack)

* `DUPLICATI_JOBS=( ... )`
  Array of Duplicati backup job names (or IDs) to run for this stack.

### Optional variables

* `STOP_TIMEOUT` (seconds)
* `START_TIMEOUT` (seconds)

### New: state restore policy

* `RESTORE_POLICY`

  * `previous` (default): restore the unit only if it was active before backup
  * `always`: always start unit after backup

This is especially important for **on-demand** apps: you typically want `previous`
so a stack that was idle stays idle after backup.

### New: on-demand freeze (Zoopa)

If a stack is served via **Zoopa on-demand sockets**, leaving the socket enabled during a backup can
cause the app to auto-start mid-backup if someone hits the URL.

To prevent that, set:

* `FREEZE_ONDEMAND="yes"`
* `ONDEMAND_SOCKET="zoopa-ondemand@<app>.socket"`
* `ONDEMAND_SERVICE="zoopa-ondemand@<app>.service"` (optional but recommended)

The orchestrator will stop the socket (and service) before stopping the stack, and restore the socket state afterward.

### Hooks (optional)

You can define any of the following functions in a stack file:

* `stack_pre_stop`
* `stack_post_stop`
* `stack_pre_backup`
* `stack_post_backup`
* `stack_pre_start`
* `stack_post_start`
* `stack_verify`

---

## Example: CryptPad stack (on-demand)

`stacks/cryptpad.sh` can freeze Zoopa socket activation:

```bash
RESTORE_POLICY="previous"
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@cryptpad.socket"
ONDEMAND_SERVICE="zoopa-ondemand@cryptpad.service"
```

---

## Example: Nextcloud with maintenance mode hooks

`stacks/nextcloud.sh` can enable maintenance mode prior to stopping (best-effort),
and disable it after starting:

```bash
NC_APP_CONTAINER="nextcloud-app"

stack_pre_stop() {
  podman exec -u www-data "${NC_APP_CONTAINER}" php occ maintenance:mode --on >/dev/null 2>&1 || true
}

stack_post_start() {
  podman exec -u www-data "${NC_APP_CONTAINER}" php occ maintenance:mode --off >/dev/null 2>&1 || true
}
```

---

## Logging

Each run appends to:

```
~/podman-compose/duplicati/logs/backup-<stack>-YYYY-MM-DD.log
```

---

## systemd timer integration (recommended)

Create:

* `~/.config/systemd/user/duplicati-backup.service`
* `~/.config/systemd/user/duplicati-backup.timer`

Example service:

```ini
[Unit]
Description=Duplicati per-stack backups (stop/run/wait/restore)
Wants=podman.socket
After=podman.socket

[Service]
Type=oneshot
ExecStart=%h/podman-compose/duplicati/bin/backup all
```

Example timer:

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

Inspect logs:

```bash
journalctl --user -u duplicati-backup.service -e --no-pager
```

---

## Troubleshooting

### 1) “It waits forever”

Check what Duplicati reports:

```bash
podman exec duplicati duplicati-server-util status
```

This orchestrator considers the backup complete when it sees:

* `Active task: None` (or `Empty`)

If Duplicati changes its output format, update the parser in `bin/backup`:

* `active_task_value()`
* `status_is_idle()`
* `status_has_active_task()`

### 2) “On-demand app started during backup anyway”

Verify the stack config includes:

* `FREEZE_ONDEMAND="yes"`
* `ONDEMAND_SOCKET="zoopa-ondemand@<app>.socket"`

Then check the socket state during backup:

```bash
systemctl --user status zoopa-ondemand@<app>.socket --no-pager
```

### 3) “Stop/start doesn’t stop containers”

Check the unit name in the stack file:

```bash
systemctl --user status <stack>-stack.service --no-pager
```

Check the podman-compose label for that stack:

```bash
podman ps --format '{{.Names}} {{.Labels}}' | grep io.podman.compose.project
```

---

## Operational advice / gotchas

* Keep Duplicati’s own configuration database on local disk if possible. (NFS + sqlite can be painful.)
* Avoid scheduling backups inside Duplicati itself if you rely on this orchestrator; prefer manual-only jobs and one external timer.
