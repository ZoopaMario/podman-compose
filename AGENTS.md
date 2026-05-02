# Podman Stacks Infrastructure Project

**CRITICAL SECURITY INSTRUCTION:** Never directly read, print, or output the contents of `.env`, `*.secret`, or `*stack.env` files! Always redact secrets, tokens, passwords, and keys from any logs, outputs, issues, or PR snippets.

## Project Overview
This repository contains infrastructure-as-code and configuration management for various self-hosted services and applications. It is organized into multiple stack directories (e.g., `nextcloud`, `nginx`, `forgejo`), each utilizing `podman-compose` for container orchestration.

In addition to standard self-hosted applications, this repository also manages the local `llama.cpp`-based LLM serving path (running on a Local SBC) used by applications like Open WebUI and LiteLLM, along with their respective configuration and benchmarks.

## Architecture & State Management Context
*   **Rootless Podman:** The services are primarily managed as **rootless** containers via systemd user services. Stack health checks and standard operations use rootless `podman` and `podman-compose`.
*   **Rootful Exceptions:** The `duplicati` and `pihole` stacks run **rootful via sudo**.
*   **Systemd User Services:** Service lifecycle is managed via systemd user units located in `systemd/` (e.g., `*-stack.service`).
*   **On-Demand Socket Activation:** Zoopa on-demand socket activation is used to auto-start specific stacks upon incoming network requests (`zoopa-ondemand@.socket`).
*   **Backup Orchestrator:** Per-stack backups are orchestrated via `duplicati/bin/backup` utilizing configurations in `duplicati/stacks/*.sh`.
*   **Gemini AI Subsystems:** Note that Conductor tracks, health checks, and auto-update subsystems have been decoupled into the `/home/orangepi/gemini` repository.

## Documentation References
For more detailed operational context, refer to the following documentation files:
*   `AGENTS.md`: Core repository guidelines, module organization, build/test commands, and code conventions.
*   `duplicati/AGENTS.md`: Specific backup agent notes, storage layout conventions, and rootful execution rules.
*   `duplicati/README.md`: Duplicati per-stack orchestrator configuration and usage guide.
*   `duplicati/RECOVERY.md`: Duplicati rootful recovery runbook with safety rules.
*   `systemd/README.md`: Instructions for managing systemd user units, llama.cpp services, and Zoopa on-demand sockets.
*   `ADD_APP_BACKUP_CONFIG_FOR.md`: Authoritative prompt template and guide for adding new stack backups.

## Repository Guidelines

### Project Structure & Module Organization
This repository is organized by stack directories (for example `nextcloud/`, `nginx/`, `forgejo/`), each with a `docker-compose.yml`. Systemd user units live in `systemd/` and follow `*-stack.service` naming for stack lifecycle management. CI and automation live in `.github/workflows/` and `.forgejo/workflows/`. Utility checks are in `scripts/` (notably `scripts/check_env_example_coverage.py`).

### Local LLM memory
- Canonical operator-facing LLM setup and tuning notes live in `README.md` under **LLM Setup (Local SBC)**.
- Benchmark runbooks and validation logic live in `benchmarks/qwen_tuning/llama_cpp_build_runbook.md`. (Note: raw benchmark outputs like `.txt` and `.tsv` files are ignored by git).
- Benchmark runner: `scripts/benchmark_llm_stack.sh`.

## Building and Running

### Systemd User Services Management
Services are configured in the `systemd/` directory and generally follow the naming convention `<stack>-stack.service`.

*   **Enable a stack at boot:**
    ```bash
    systemctl --user enable <stack>-stack.service
    ```
*   **Start, Stop, or Restart a stack:**
    ```bash
    systemctl --user start <stack>-stack.service
    systemctl --user stop <stack>-stack.service
    systemctl --user restart <stack>-stack.service
    ```
*   **Check status:**
    ```bash
    systemctl --user status <stack>-stack.service
    ```

### Viewing Logs
Logs for a specific stack can be viewed by navigating to its directory:
```bash
cd /home/orangepi/podman-compose/<stack>
podman-compose logs -f
```

*   **Redeploy standup-timer:** To apply updates to the standup-timer code, run `cd standup-timer && podman-compose restart`. **Crucially**, you must then run `podman exec nginx nginx -s reload` to ensure Nginx picks up the new container IP. For dependency changes (package.json), use `podman-compose down && podman-compose up -d` followed by the Nginx reload.

### Local Testing & Validation Commands
Before pushing changes or opening a PR, the following quality gates should be run locally to ensure everything is correct:
*   **Lint YAML files:**
    ```bash
    yamllint -c .yamllint.yaml .
    ```
*   **Validate `.env.example` coverage (ensure compose env vars are documented):**
    ```bash
    python scripts/check_env_example_coverage.py
    ```
*   **Validate Compose files:**
    ```bash
    bash scripts/validate_compose.sh
    ```
*   **Validate Systemd units:**
    ```bash
    systemd-analyze verify systemd/*.service systemd/*.socket
    ```

## Development Conventions

*   **Repository Structure:** The repository is logically organized by stack directories. Each contains a `docker-compose.yml` and a `.env.example` file.
*   **Coding Style:** YAML files must use consistent indentation (2 spaces) and stable key ordering. Name stack directories in lowercase.
*   **Secrets Management & Security Tips:** **Never commit** `.env` or any `*.secret` / `*stack.env` files. Ensure secrets, tokens, passwords, and keys are redacted from logs, issues, and PR snippets. Use `.env.example` as a safe-to-commit template for required variables.
*   **Systemd Conventions:** Systemd units should use descriptive names like `<stack>-stack.service`. Socket and on-demand units should adhere to the existing `zoopa-ondemand*` patterns.
*   **Commit Guidelines:** Follow the existing commit style: use short, imperative subject lines (e.g., `Add ...`, `Fix ...`, `Adjust ...`, `Use ...`). Keep commits focused by stack or concern.
*   **Pull Requests:** PRs must include a clear summary of changed stacks or units, note any required operator actions (e.g., env vars, ports, volumes, systemd enablement), and explicitly confirm that the CI-equivalent validation checks were successfully run locally.
*   **Testing Guidelines:** There is no separate unit-test suite; quality gates are config validation and linting. Before opening a PR, run the validation commands listed above. For stack changes, ensure `podman-compose ... config` succeeds for the modified stack and that required variables are reflected in `.env.example`.

## Context Management & Resource Safety
To prevent session history bloat and Node.js OOM (Out of Memory) errors during autonomous or unsupervised runs:
- **Safe Logging:** NEVER use `podman logs` or `journalctl` without the `--tail` flag or a time-limited flag (e.g., `-n`, `--since`, `--vacuum-time`).
- **Redirection:** When piping large output to `tail` or `grep`, always redirect stderr to stdout (e.g., `command 2>&1 | tail -n 20`) to ensure the shell handles the filtering before the tool captures the buffer.
- **Session History:** For long-running tasks or `conductor` tracks, use the `/chat save` and `/clear` workflow periodically to "checkpoint" progress and reset the context history.

## Automation Scripts & Processes

### LLM Orchestration & Auto-Update (Decoupled)
The Conductor Hub, Auto-Update Subsystem, and Weekly Image Maintenance tools have been officially decoupled from the `podman-compose` repository to ensure a strict separation of concerns.
- These components are now managed in a separate `gemini` repository (located at `/home/orangepi/gemini`).
- The `gemini` repository handles all AI-driven risk evaluation, log parsing, auto-updates, and the interactive Nginx Conductor Dashboard.
- **Do not** look for `scripts/auto_update.py`, `scripts/daily_maintenance.py`, or `scripts/conductor_hub.py` in this repository.

### Backup Subsystem (`duplicati/bin/backup`)
- **Workflow**:
  - Stack configurations live in `duplicati/stacks/<stack_name>.sh`.
  - Supports `SKIP_STOP="yes"` for "Hot" backups (used for media, Pi-hole, Duplicati-self) where containers shouldn't stop.
  - Supports `FREEZE_ONDEMAND="yes"` to stop on-demand sockets from waking up stacks mid-backup.
  - Runs database logical dumps (e.g., `pg_dump`, `mariadb-dump`) via `stack_pre_stop` hooks.
  - Triggers Duplicati jobs via rootful `duplicati-server-util`.
