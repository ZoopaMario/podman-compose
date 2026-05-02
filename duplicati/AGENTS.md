# Duplicati Backup Agent Notes

## Scope

Applies to `duplicati/` only. Purpose: keep per-stack backups predictable and safe with a **rootful Duplicati** container while other stacks remain rootless under `systemd --user`.

## Environment Snapshot (non-secret)

- User runtime model:
  - user: `orangepi` (`uid=1000`, `gid=1000`)
  - `XDG_RUNTIME_DIR=/run/user/1000`
- Host/runtime:
  - Linux kernel: `6.6.89-cix` on `aarch64`
  - Podman: `4.3.1`
  - podman-compose: `1.0.3`
  - systemd: `252`
- Operational implication:
  - Duplicati runs **rootful** via sudo (podman/podman-compose).
  - Other stacks remain **rootless**, with storage under `%h/.local/share/containers/storage`.
  - on-demand sockets live under `%t/ondemand` (`/run/user/1000/ondemand`)
  - Do not run a rootless Duplicati instance in parallel.

## Source Of Truth

- Runtime behavior:
  - `duplicati/bin/backup`
- Per-stack declarations:
  - `duplicati/stacks/*.sh`
- Operator docs:
  - `duplicati/README.md`
  - `systemd/README.md`
- Scheduler units:
  - `systemd/duplicati-backup.service`
  - `systemd/duplicati-backup.timer`
- On-demand activation units:
  - `systemd/zoopa-ondemand@.socket`
  - `systemd/zoopa-ondemand@.service`
  - `systemd/zoopa-ondemand-stop@.service`
  - `systemd/zoopa-ondemand-dir.service`

## Current Backup Automation State

- Automated schedule exists via timer:
  - `OnCalendar=*-*-* 03:30:00`
  - `Persistent=true`
- Automated target scope is explicit and intentionally narrow:
  - `systemd/duplicati-backup.service` runs:
    - `%h/podman-compose/duplicati/bin/backup cryptpad`
- Policy in this repo:
  - manually validate each new app stack first
  - then append the stack name to the `ExecStart` argument list
  - do not switch automation to `backup all` unless explicitly requested

## Core Orchestrator Model (`bin/backup`)

- One stack config file per stack: `stacks/<stack>.sh`.
- CLI supports:
  - `list`
  - `all`
  - explicit stack/unit args
- Arguments are normalized by stripping path, `-stack.service`, `.service`.
- Global lock:
  - lock file at `${XDG_RUNTIME_DIR:-/tmp}/duplicati-backup.lock`
  - prevents concurrent runs.
- Duplicati health gate:
  - container must be running (rootful podman)
  - `duplicati-server-util list-backups` must succeed.
- Stack execution flow:
  1. Optional freeze of on-demand socket/service.
  2. Stop stack unit.
  3. Wait for project containers to stop by label `io.podman.compose.project=<PROJECT_LABEL>`.
  4. Run configured Duplicati jobs.
  5. Wait for completion.
  6. Restore stack based on restore policy.
  7. Optionally restore on-demand socket.
  8. Run optional verification hook.
- Backup completion logic is conservative:
  - prefers `run --wait` when supported
  - otherwise polls status
  - treats explicit idle (`Active task: None|Empty` or idle text) as success
  - unknown status format does not auto-pass; it keeps waiting until timeout.
- Timeout defaults:
  - enqueue timeout (`DUPLICATI_RUN_TIMEOUT`): `25s`
  - max backup wait (`DUPLICATI_WAIT_TIMEOUT`): `21600s` (6h)
  - per-stack start/stop waits default to `180s` unless overridden.
  - podman command override (`PODMAN_CMD`): `sudo -n podman` by default
- Cleanup trap:
  - best-effort restoration of stack and on-demand socket state after failures.

## Stack Config Contract (`duplicati/stacks/*.sh`)

- Required:
  - `STACK_NAME` (fallback filename)
  - `UNIT` (fallback `<stack>-stack.service`)
  - `PROJECT_LABEL` (fallback `<stack>`)
  - `DUPLICATI_JOBS` (non-empty)
- Optional:
  - `STOP_TIMEOUT`, `START_TIMEOUT`
  - `RESTORE_POLICY=previous|always` (default `previous`)
  - `FREEZE_ONDEMAND=yes|no` with `ONDEMAND_SOCKET` and optional `ONDEMAND_SERVICE`
  - hooks:
    - `stack_pre_stop`, `stack_post_stop`
    - `stack_pre_backup`, `stack_post_backup`
    - `stack_pre_start`, `stack_post_start`
    - `stack_verify`
- Existing examples:
  - `cryptpad.sh`:
    - `RESTORE_POLICY=previous`
    - `FREEZE_ONDEMAND=yes`
    - freezes `zoopa-ondemand@cryptpad.socket` and `zoopa-ondemand@cryptpad.service`
  - `nextcloud.sh`:
    - maintenance mode toggle via `occ` around stop/start

## On-demand Interaction Model

- Reverse proxy integration:
  - `nginx` mounts `/run/user/1000/ondemand` as `/sockets:ro`
- On-demand stacks can be identified by filename pattern in `systemd/`:
  - `cryptpad-stack-ondemand.env`
  - `homarr-stack-ondemand.env`
  - `romm-stack-ondemand.env`
- Operational behavior:
  - `.socket` listens on `%t/ondemand/%i.sock`
  - first request triggers `.service`, which can start `%i-stack.service`
  - idle helper may stop stack if started by on-demand marker
  - backup flow may freeze/unfreeze socket to avoid surprise reactivation mid-backup

## Storage Layout Conventions (backup-relevant)

- Common persistent roots used in compose files:
  - `${DATA_ROOT:-/mnt/data}` for app data on shared storage
  - `${LOCAL_ROOT:-/srv}` for local-disk state
- Duplicati stack mounts:
  - local state DB: `${LOCAL_ROOT:-/srv}/duplicati/data` -> `/data`
  - source tree root: `${DATA_ROOT:-/mnt/data}` mounted read-only
  - backup destination: `/mnt/backup`
  - rootless named volumes path read-only:
    - `${HOST_HOME}/.local/share/containers/storage/volumes` -> `/podman-volumes`
- Implication:
  - if an app uses named volumes for DB state, include corresponding volume path data in backup scope (directly or via dumps).

## Backup-Relevant Stack Inventory (current repo)

- `cryptpad`:
  - app data bind mounts under `${DATA_ROOT}/cryptpad/*`
  - no separate DB container in compose.
- `nextcloud`:
  - app data/config at `${LOCAL_ROOT}/nextcloud/*` and `${DATA_ROOT}/nextcloud/data`
  - MariaDB data in named volume `nextcloud-db-data`
  - Redis configured as cache (`appendonly no`, no snapshot save).
- `forgejo`:
  - persistent paths under `${DATA_ROOT}/forgejo/{conf,data,runner-data}`
  - no separate DB service in current compose.
- `vaultwarden`:
  - persistent path `${DATA_ROOT}/vaultwarden:/data`.
- `jellyfin`:
  - config/cache under `${LOCAL_ROOT}/jellyfin/{config,cache}`
  - media under `${DATA_ROOT}/MEDIA` bind mount.
- `shlink`:
  - MariaDB data at `${DATA_ROOT}/shlink/db`.
- `immich`:
  - uploads at `${UPLOAD_LOCATION}`
  - Postgres data in named volume `immich-db-data`
  - model cache in named volume `model-cache` (rebuildable but expensive).
- `open-webui`:
  - app backend data at `${DATA_ROOT}/open-webui/owui`
  - qdrant data at `${DATA_ROOT}/open-webui/qdrant`
  - mcpo config at `${DATA_ROOT}/open-webui/mcpo`
  - Postgres data in named volume `owui-postgres-data`
  - valkey configured non-persistent.
- `romm`:
  - persistent content/config/assets under `${DATA_ROOT}/romm/*` and media library path
  - MariaDB data in named volume `mysql_data`
  - redis data in named volume `romm_redis_data` (cache-ish but currently persisted).
- `litellm`:
  - Postgres data in external named volume `litellm-db-data`.
- `openqa/prod`:
  - Postgres bind mount `/srv/openqa/prod/postgres`
  - additional persistent dirs: `./share`, `./db`, `./pool`, `./testresults`, `./images`, config dirs.
- `parabol`:
  - Postgres bind mount `/srv/parabol/postgres/pgdata`
  - additional config bind mount under `/mnt/data/parabol/config`.
- `pihole`:
  - persistent bind `${LOCAL_ROOT}/pihole/etc-pihole`
  - unbound state named volume `unbound_state`.
- `grafana`:
  - `${DATA_ROOT}/grafana/data`
  - `${DATA_ROOT}/prometheus/data`
  - config mounts under `${DATA_ROOT}/grafana/conf` and `${DATA_ROOT}/prometheus`.
- `homarr`:
  - persistent `${DATA_ROOT}/homarr/appdata`.
- `fmd-server`:
  - persistent bind `/srv/fmd-server/fmddata/db`.
- `collabora`:
  - no persistent volume declared in current compose.
- `nginx`:
  - certs/config under `${DATA_ROOT}/nginx/*`
  - reverse-proxy content mounts for Nextcloud/CryptPad.

## Reliability Notes For Future Stack Onboarding

- DB-backed apps:
  - prefer consistent DB dumps/hooks where app docs require them
  - if relying on cold backups (stack stop + volume copy), verify restore procedure for that DB engine.
- Cache services:
  - valkey/redis instances often intentionally non-persistent here
  - do not classify cache-only data as mandatory restore data.
- NFS/local split:
  - project docs explicitly warn against placing container storage on NFS
  - bind-mounted persistent data on NFS is used intentionally.
- Rootless nuance:
  - several compose files run container user `"0"` with rootless mapping semantics.

## Validation And CI Gates

- Local checks used in repo:
  - `yamllint -c .yamllint.yaml .`
  - `python scripts/check_env_example_coverage.py`
  - `bash scripts/validate_compose.sh`
  - `systemd-analyze verify systemd/*.service systemd/*.socket`
- CI (`.github/workflows/ci.yml`, `.forgejo/workflows/ci.yml`) enforces the same quality gates.

## Add/Change Stack Checklist

1. Confirm official app backup requirements and consistency expectations.
2. Identify mandatory persistent paths and DB data locations from compose/systemd.
3. Create/verify Duplicati jobs with stable names.
4. Implement/update `duplicati/stacks/<stack>.sh`.
5. Validate mapping:
   - `systemctl --user status <unit> --no-pager`
   - `podman ps --format '{{.Names}} {{.Labels}}' | grep io.podman.compose.project=<label>`
6. Run manual test:
   - `~/podman-compose/duplicati/bin/backup <stack>`
7. Review per-stack log:
   - `duplicati/logs/backup-<stack>-YYYY-MM-DD.log`
8. Only after manual success, append stack arg in:
   - `systemd/duplicati-backup.service` `ExecStart=...`
9. Reload and keep timer enabled:
   - `systemctl --user daemon-reload`
   - `systemctl --user enable --now duplicati-backup.timer`

## Security / Secret Handling

- Never read or print:
  - `.env`
  - `*.env`
  - `*stack.env`
- Never print:
  - credentials, tokens, secret keys, passphrases
  - remote URLs containing embedded authentication
- When reporting logs/config:
  - summarize and redact sensitive values.
