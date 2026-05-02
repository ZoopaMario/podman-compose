STACK_NAME="open-webui"
UNIT="open-webui-stack.service"
PROJECT_LABEL="open-webui"

DUPLICATI_JOBS=(
  "Open WebUI -> Remote"
  "Open WebUI -> Local"
)

# Open WebUI uses Postgres and Qdrant. We'll use pg_dump for the DB.
OWUI_DB_CONTAINER="open-webui_postgres_1"
OWUI_BACKUP_DIR="/mnt/data/open-webui/backups"

stack_pre_stop() {
  local ts out_file
  mkdir -p "${OWUI_BACKUP_DIR}"
  
  if ! podman ps --format '{{.Names}}' | grep -qx "${OWUI_DB_CONTAINER}"; then
    log "Open WebUI: DB container '${OWUI_DB_CONTAINER}' not running, skipping logical dump."
    return 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${OWUI_BACKUP_DIR}/owui-db-${ts}.sql.gz"

  log "Open WebUI: Creating Postgres dump: ${out_file}"
  # PGPASSWORD is used for auth.
  if ! podman exec "${OWUI_DB_CONTAINER}" sh -c 'PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -U "${POSTGRES_USER:-openwebui}" "${POSTGRES_DB:-openwebui}"' | gzip -9 > "${out_file}"; then
    log "ERROR: Open WebUI: pg_dump failed!"
    return 1
  fi
  
  ls -t "${OWUI_BACKUP_DIR}"/owui-db-*.sql.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

RESTORE_POLICY="previous"
STOP_TIMEOUT=300
START_TIMEOUT=300

stack_verify() {
  :
}
