# Duplicati Recovery Runbook (Rootful)

This runbook is **duplicati-only**. All other stacks remain rootless.

## Preconditions (must verify)

- Duplicati container is running rootful and reachable:
  - `sudo podman ps --format '{{.Names}}' | grep -qx duplicati`
  - `sudo podman exec duplicati duplicati-server-util list-backups`
- Target mount is writable:
  - `stat -c '%A %U:%G %n' /mnt/data`
- Backup destination is reachable:
  - `ls -la /mnt/backup >/dev/null`

## Safety Rules (non-negotiable)

- First copy pass is **never** destructive.
- Do not use `--delete` on the first pass.
- Always sanity-check source and destination paths before copy:
  - `pwd`
  - `stat -c '%n' /mnt/data /srv/duplicati/data`
  - `echo "SRC=$SRC" && echo "DST=$DST"`
- Prefer staging restores before in-place overwrite.

## Staged Restore (Recommended)

1. Create a staging directory:
   - `ts=$(date +%F-%H%M%S)`
   - `stage="/srv/duplicati/data/restore/${ts}"`
   - `mkdir -p "${stage}"`
2. Run restore in Duplicati UI into `${stage}`.
3. Validate critical files:
   - `test -s "${stage}/vaultwarden/db.sqlite3"`
   - `sqlite3 "${stage}/vaultwarden/db.sqlite3" "PRAGMA integrity_check;"`
4. Non-destructive merge into live path:
   - `rsync -avh --progress "${stage}/vaultwarden/" "/mnt/data/vaultwarden/"`
5. Only after verification + dry-run:
   - `rsync -avh --dry-run --delete "${stage}/vaultwarden/" "/mnt/data/vaultwarden/"`
   - If the dry-run output is correct, re-run with `--delete`.

## Direct Restore (Only When Explicitly Required)

- Confirm mount is RW and target path is correct.
- Restore directly into `/mnt/data/<app>`.
- Immediately verify DB integrity after restore.

## Post-Restore Validation (Vaultwarden Example)

- `test -s /mnt/data/vaultwarden/db.sqlite3`
- `sqlite3 /mnt/data/vaultwarden/db.sqlite3 "PRAGMA integrity_check;"`
- Spot-check at least one attachment file.

## Observability

- Check Duplicati status:
  - `sudo podman exec duplicati duplicati-server-util status`
- Backup logs (per stack):
  - `~/podman-compose/duplicati/logs/backup-<stack>-YYYY-MM-DD.log`
