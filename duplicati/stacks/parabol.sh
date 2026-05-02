STACK_NAME="parabol"
UNIT="parabol-stack.service"
PROJECT_LABEL="parabol"

DUPLICATI_JOBS=(
  "Parabol -> Remote"
  "Parabol -> Local"
)

# On-demand stack: freeze socket
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@parabol.socket"
ONDEMAND_SERVICE="zoopa-ondemand@parabol.service"

PARABOL_DB_CONTAINER="parabol-postgres"
PARABOL_BACKUP_DIR="/mnt/data/parabol/backups"

stack_pre_stop() {
  local ts out_file
  mkdir -p "${PARABOL_BACKUP_DIR}"
  
  if ! podman ps --format '{{.Names}}' | grep -qx "${PARABOL_DB_CONTAINER}"; then
    log "Parabol: DB container '${PARABOL_DB_CONTAINER}' not running, skipping logical dump."
    return 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${PARABOL_BACKUP_DIR}/parabol-db-${ts}.sql.gz"

  log "Parabol: Creating Postgres dump: ${out_file}"
  # Note: PGPASSWORD is used for auth, variables are inside container env.
  if ! podman exec "${PARABOL_DB_CONTAINER}" sh -c 'PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -U "${POSTGRES_USER:-pgparaboladmin}" "${POSTGRES_DB:-parabol-saas}"' | gzip -9 > "${out_file}"; then
    log "ERROR: Parabol: pg_dump failed!"
    return 1
  fi
  
  ls -t "${PARABOL_BACKUP_DIR}"/parabol-db-*.sql.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

RESTORE_POLICY="previous"
STOP_TIMEOUT=180
START_TIMEOUT=180

stack_verify() {
  :
}
