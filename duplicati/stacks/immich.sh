STACK_NAME="immich"
UNIT="immich-stack.service"
PROJECT_LABEL="immich"

DUPLICATI_JOBS=(
  "Immich -> Remote"
  "Immich -> Local"
)

STOP_TIMEOUT=240
START_TIMEOUT=240
RESTORE_POLICY="previous"

IMMICH_SERVER_CONTAINER="${IMMICH_SERVER_CONTAINER:-immich_server}"
IMMICH_DB_CONTAINER="${IMMICH_DB_CONTAINER:-immich_postgres}"
IMMICH_UPLOAD_PATH="${IMMICH_UPLOAD_PATH:-}"
IMMICH_DB_DUMP_PREFIX="${IMMICH_DB_DUMP_PREFIX:-immich-db-backup}"

immich_container_running() {
  local name="$1"
  podman ps --format '{{.Names}}' | grep -qx "${name}"
}

immich_resolve_upload_path() {
  if [[ -n "${IMMICH_UPLOAD_PATH}" ]]; then
    echo "${IMMICH_UPLOAD_PATH}"
    return
  fi

  local detected
  detected="$(
    podman inspect -f '{{ range .Mounts }}{{ if eq .Destination "/usr/src/app/upload" }}{{ .Source }}{{ end }}{{ end }}' "${IMMICH_SERVER_CONTAINER}" 2>/dev/null \
      | head -n1 \
      | xargs || true
  )"
  if [[ -n "${detected}" ]]; then
    echo "${detected}"
    return
  fi

  echo "/mnt/data/immich/uploads"
}

stack_pre_stop() {
  local upload_path backups_dir ts out_file tmp_file
  upload_path="$(immich_resolve_upload_path)"
  backups_dir="${upload_path}/backups"
  mkdir -p "${backups_dir}"

  if immich_container_running "${IMMICH_SERVER_CONTAINER}"; then
    log "Immich: stopping app container '${IMMICH_SERVER_CONTAINER}' before DB dump"
    podman stop -t 60 "${IMMICH_SERVER_CONTAINER}" >/dev/null
  else
    log "Immich: app container '${IMMICH_SERVER_CONTAINER}' is not running; continuing with DB dump"
  fi

  immich_container_running "${IMMICH_DB_CONTAINER}" \
    || die "Immich: DB container '${IMMICH_DB_CONTAINER}' is not running; cannot create logical backup."

  ts="$(date +%Y%m%d-%H%M%S)"
  out_file="${backups_dir}/${IMMICH_DB_DUMP_PREFIX}-${ts}.sql.gz"
  tmp_file="${out_file}.tmp"

  log "Immich: writing logical Postgres backup to ${out_file}"
  if ! podman exec "${IMMICH_DB_CONTAINER}" sh -ceu '
    export PGPASSWORD="${POSTGRES_PASSWORD:?missing POSTGRES_PASSWORD}"
    pg_dump \
      --dbname="${POSTGRES_DB:?missing POSTGRES_DB}" \
      --username="${POSTGRES_USER:?missing POSTGRES_USER}" \
      --clean \
      --if-exists \
      --no-owner \
      --no-privileges
  ' | gzip -9 > "${tmp_file}"; then
    rm -f "${tmp_file}"
    die "Immich: pg_dump failed."
  fi

  mv "${tmp_file}" "${out_file}"
  chmod 600 "${out_file}" 2>/dev/null || true
  log "Immich: DB backup created: ${out_file}"
}

stack_verify() {
  local upload_path backups_dir latest
  upload_path="$(immich_resolve_upload_path)"
  backups_dir="${upload_path}/backups"
  latest="$(ls -1t "${backups_dir}/${IMMICH_DB_DUMP_PREFIX}"-*.sql.gz 2>/dev/null | head -n1 || true)"

  if [[ -z "${latest}" ]]; then
    log "WARNING: Immich: no DB dump files found in ${backups_dir}"
    return 0
  fi
  if [[ ! -s "${latest}" ]]; then
    log "WARNING: Immich: latest DB dump exists but is empty: ${latest}"
    return 0
  fi

  log "Immich: latest DB dump verified: ${latest}"
}
