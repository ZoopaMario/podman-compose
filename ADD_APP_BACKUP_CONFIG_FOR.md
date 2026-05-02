# Add App Backup Config Prompt

## Maintenance Rule (Must Follow)
Last updated: 2026-02-22
This file is the **authoritative prompt** for adding new Duplicati stack backups.
If you discover new Duplicati-relevant facts while working (paths, policies,
sudoers scope, rootful/rootless behavior, on-demand rules, etc.), you must:
1. Explicitly call out the mismatch.
2. Ask the user whether to update this file (and any memory files) accordingly.
3. If approved, apply the update before concluding.

Use this prompt in a fresh chat and append the app stack name at the end:

`APP_STACK_NAME: <stack-name>`

## Prompt

You are a senior SRE/Platform engineer. Help me add a robust Duplicati backup configuration for a specific app stack in my local `podman-compose` repository.

Repository context:
- Root path: `~/podman-compose`
- Duplicati orchestrator path: `~/podman-compose/duplicati/bin/backup`
- Per-stack config path: `~/podman-compose/duplicati/stacks/<stack>.sh`
- Scheduler service path: `~/podman-compose/systemd/duplicati-backup.service`
- Existing model: explicit stack args in scheduler `ExecStart`, not `backup all`
- Environment: rootless Podman for app stacks; Duplicati runs rootful via sudo, systemd user services

Current environment facts (must respect):
- Duplicati container is **rootful** and must be controlled via `sudo -n podman`.
- App stacks remain **rootless** and must be controlled via `systemctl --user`.
- Stack health checks must use **rootless** `podman` (not sudo) with label filters.
- The backup script uses `PODMAN_CMD` (rootful) and `PODMAN_STACK_CMD` (rootless). Do not remove them.
- On-demand stacks use `zoopa-ondemand@<stack>.socket` and should only restore the **socket** unless containers were running before backup.
- Sudoers is tightly scoped for Duplicati only; do not suggest broad sudo rules.

Quick usage examples (do not run with sudo):
- Trigger manual backup: `~/podman-compose/duplicati/bin/backup <stack>`
- List configured stacks: `~/podman-compose/duplicati/bin/backup list`
- Check Duplicati jobs (rootful): `sudo -n podman exec duplicati duplicati-server-util list-backups`

Critical constraints:
1. Never read or print any `.env`, `*.env`, or `*stack.env` files.
2. Redact secrets/tokens/passwords/keys from all outputs.
3. Preserve existing behavior unless a clear reliability or correctness issue is identified.
4. Prefer deterministic, operationally safe backup/restore steps over convenience.
5. For claims about the app backup strategy, use official upstream documentation and cite sources.
6. Do not restart on-demand stacks unless containers were running before the backup began.

Your task:
1. Identify and inspect all relevant local files for the target app stack:
   - `<app>/docker-compose.yml`
   - related systemd unit(s) in `systemd/`
   - nginx/proxy wiring if relevant
   - existing `duplicati/stacks/*.sh` patterns
2. Research official backup and restore guidance for the target app and its database(s).
3. Determine the best backup consistency method for this deployment:
   - app-level export/snapshot commands if recommended
   - maintenance/read-only mode if needed
   - database-consistent strategy (logical dump vs physical backup, WAL/binlog considerations)
   - volume/file backup requirements
4. Map the app to this repo’s backup orchestrator:
   - propose `duplicati/stacks/<app>.sh`
   - set `UNIT`, `PROJECT_LABEL`, `DUPLICATI_JOBS`, `RESTORE_POLICY`
   - add hooks (`stack_pre_stop`, `stack_post_start`, etc.) where needed
   - evaluate and configure `FREEZE_ONDEMAND` / `ONDEMAND_SOCKET` if stack is on-demand
5. Include Duplicati job creation guidance:
   - exact source paths to include/exclude
   - destination naming conventions
   - retention policy recommendation
   - schedule must be manual/off if `bin/backup`/timer drives execution
6. Produce a step-by-step implementation plan I can execute safely.
7. Provide validation and rollback checks.
8. If changes are needed, provide exact patch-ready file edits.
9. Finally, propose the exact `ExecStart` line update in `systemd/duplicati-backup.service` to append this app only after manual test success.

Required output format:

1. `Assumptions`
2. `Files Reviewed`
3. `Official Backup Guidance Summary` (with links)
4. `Backup Design For This Deployment`
5. `Database Backup Strategy`
6. `Exact Paths To Back Up`
7. `Step-by-Step Implementation`
8. `Proposed File Changes`
9. `Validation Checklist`
10. `Rollback Plan`
11. `Scheduler Update` (explicit `ExecStart` args)
12. `Open Questions / Risks`

Quality bar:
- Be explicit about why each path and hook exists.
- Call out app-specific quirks (permissions, background workers, object storage, encryption keys, caches, generated artifacts).
- Distinguish mandatory backup data from regenerable/transient data.
- Include restore-test recommendations, not only backup steps.
- If official guidance conflicts with local constraints, explain tradeoffs and pick the safest feasible approach.
