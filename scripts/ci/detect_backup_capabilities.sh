#!/usr/bin/env bash
set -euo pipefail

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

has_podman="false"
can_run_podman="false"
has_systemd_user="false"
can_use_systemctl_user="false"
can_run_full_backup_integration="false"

if has_cmd podman; then
  has_podman="true"
  if podman info >/dev/null 2>&1; then
    can_run_podman="true"
  fi
fi

if has_cmd systemctl; then
  has_systemd_user="true"
  if systemctl --user list-unit-files >/dev/null 2>&1; then
    can_use_systemctl_user="true"
  fi
fi

if [[ "$can_run_podman" == "true" && "$can_use_systemctl_user" == "true" ]]; then
  can_run_full_backup_integration="true"
fi

echo "HAS_PODMAN=$(bool "$has_podman")"
echo "CAN_RUN_PODMAN=$(bool "$can_run_podman")"
echo "HAS_SYSTEMD_USER=$(bool "$has_systemd_user")"
echo "CAN_USE_SYSTEMCTL_USER=$(bool "$can_use_systemctl_user")"
echo "CAN_RUN_FULL_BACKUP_INTEGRATION=$(bool "$can_run_full_backup_integration")"
