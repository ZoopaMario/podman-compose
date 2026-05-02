STACK_NAME="romm"
UNIT="romm-stack.service"
PROJECT_LABEL="romm"

DUPLICATI_JOBS=(
  "Romm -> Remote"
  "Romm -> Local"
)

# On-demand stack
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@romm.socket"
ONDEMAND_SERVICE="zoopa-ondemand@romm.service"

ROMM_DB_CONTAINER="romm_romm-db_1"
ROMM_BACKUP_DIR="/mnt/data/romm/backups"

stack_pre_stop() {
  local ts out_file
  mkdir -p "${ROMM_BACKUP_DIR}"
  
  if ! podman ps --format '{{.Names}}' | grep -qx "${ROMM_DB_CONTAINER}"; then
    log "Romm: DB container '${ROMM_DB_CONTAINER}' not running, skipping logical dump."
    return 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${ROMM_BACKUP_DIR}/romm-db-${ts}.sql.gz"

  log "Romm: Creating MariaDB dump: ${out_file}"
  # Using MYSQL_PWD is a common way to pass the password to dump via env
  if ! podman exec "${ROMM_DB_CONTAINER}" sh -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mariadb-dump -u root --all-databases' | gzip -9 > "${out_file}"; then
    log "ERROR: Romm: mariadb-dump failed!"
    return 1
  fi
  
  ls -t "${ROMM_BACKUP_DIR}"/romm-db-*.sql.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

RESTORE_POLICY="previous"
STOP_TIMEOUT=180
START_TIMEOUT=180

stack_verify() {
  :
}
