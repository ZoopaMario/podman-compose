STACK_NAME="litellm"
UNIT="litellm-stack.service"
PROJECT_LABEL="litellm"

DUPLICATI_JOBS=(
  "LiteLLM -> Remote"
  "LiteLLM -> Local"
)

# LiteLLM uses a Postgres DB in a named volume 'litellm-db-data'.
# We'll use a pre-stop hook to create a logical dump for better portability.
LITELLM_DB_CONTAINER="litellm_db_1"
LITELLM_BACKUP_DIR="/mnt/data/litellm/backups"

stack_pre_stop() {
  local ts out_file
  mkdir -p "${LITELLM_BACKUP_DIR}"
  
  # Check if DB is running
  if ! podman ps --format '{{.Names}}' | grep -qx "${LITELLM_DB_CONTAINER}"; then
    log "LiteLLM: DB container '${LITELLM_DB_CONTAINER}' not running, skipping logical dump."
    return 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${LITELLM_BACKUP_DIR}/litellm-db-${ts}.sql.gz"

  log "LiteLLM: Creating Postgres dump: ${out_file}"
  # We use 'podman exec' to run pg_dump inside the container.
  if ! podman exec "${LITELLM_DB_CONTAINER}" sh -c 'PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -U "${POSTGRES_USER:-llmproxy}" "${POSTGRES_DB:-litellm}"' | gzip -9 > "${out_file}"; then
    log "ERROR: LiteLLM: pg_dump failed!"
    return 1
  fi
  
  # Keep only last 5 dumps locally to save space
  ls -t "${LITELLM_BACKUP_DIR}"/litellm-db-*.sql.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

RESTORE_POLICY="previous"
STOP_TIMEOUT=180
START_TIMEOUT=180

stack_verify() {
  :
}
