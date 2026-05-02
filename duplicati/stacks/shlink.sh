STACK_NAME="shlink"
UNIT="shlink-stack.service"
PROJECT_LABEL="shlink"

DUPLICATI_JOBS=(
  "Shlink -> Remote"
  "Shlink -> Local"
)

RESTORE_POLICY="previous"
STOP_TIMEOUT=180
START_TIMEOUT=180

SHLINK_DB_CONTAINER="my_shlink_db"
SHLINK_BACKUP_DIR="/mnt/data/shlink/backups"

stack_pre_stop() {
  local ts out_file
  mkdir -p "${SHLINK_BACKUP_DIR}"
  
  if ! podman ps --format '{{.Names}}' | grep -qx "${SHLINK_DB_CONTAINER}"; then
    log "Shlink: DB container '${SHLINK_DB_CONTAINER}' not running, skipping logical dump."
    return 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${SHLINK_BACKUP_DIR}/shlink-db-${ts}.sql.gz"

  log "Shlink: Creating MariaDB dump: ${out_file}"
  # Using shlink_user for the dump as it has direct access to the db
  if ! podman exec "${SHLINK_DB_CONTAINER}" sh -c 'MYSQL_PWD="${MYSQL_PASSWORD}" mariadb-dump -u "${MYSQL_USER}" "${MYSQL_DATABASE}"' | gzip -9 > "${out_file}"; then
    log "ERROR: Shlink: mariadb-dump failed!"
    return 1
  fi
  
  log "Shlink: Flushing InnoDB change buffer before shutdown..."
  # Using root via socket auth for SUPER privilege to ensure clean shutdown for the MariaDB 11.4 upgrade
  if ! podman exec "${SHLINK_DB_CONTAINER}" mariadb -u root -e "SET GLOBAL innodb_fast_shutdown=0;"; then
    log "WARNING: Shlink: Failed to set innodb_fast_shutdown=0!"
  fi
  
  ls -t "${SHLINK_BACKUP_DIR}"/shlink-db-*.sql.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

stack_verify() {
  :
}