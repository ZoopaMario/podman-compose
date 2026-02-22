STACK_NAME="nextcloud"
UNIT="nextcloud-stack.service"
PROJECT_LABEL="nextcloud"

DUPLICATI_JOBS=(
  "Nextcloud -> Remote"
)

# Adjust if your container name differs:
NC_APP_CONTAINER="nextcloud-app"

# Retry tuning (seconds/retries) for OCC calls around startup/shutdown.
NC_OCC_RETRY_COUNT="${NC_OCC_RETRY_COUNT:-24}"
NC_OCC_RETRY_SLEEP="${NC_OCC_RETRY_SLEEP:-5}"
NC_OCC_TIMEOUT="${NC_OCC_TIMEOUT:-20}"

nc_occ() {
  timeout "${NC_OCC_TIMEOUT}" podman exec -u www-data "${NC_APP_CONTAINER}" php occ "$@"
}

normalize_maintenance_state() {
  local raw
  raw="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "${raw}" in
    true|enabled|on|yes) echo "true" ;;
    false|disabled|off|no) echo "false" ;;
    *) echo "" ;;
  esac
}

wait_for_maintenance_state() {
  local wanted="$1"
  local i out state

  for ((i = 1; i <= NC_OCC_RETRY_COUNT; i++)); do
    out="$(nc_occ status 2>/dev/null || true)"
    state="$(
      echo "${out}" \
        | sed -n 's/^[[:space:]-]*maintenance:[[:space:]]*//p' \
        | head -n1
    )"
    state="$(normalize_maintenance_state "${state}")"
    if [[ "${state}" == "${wanted}" ]]; then
      return 0
    fi
    if (( i == 1 || i % 6 == 0 )); then
      log "Nextcloud: waiting for maintenance=${wanted} (attempt ${i}/${NC_OCC_RETRY_COUNT})"
    fi
    sleep "${NC_OCC_RETRY_SLEEP}"
  done
  return 1
}

stack_pre_stop() {
  local i

  # Put Nextcloud into maintenance mode before stopping.
  # If www-data user doesn't exist in your image, remove -u.
  log "Nextcloud: enabling maintenance mode"
  for ((i = 1; i <= NC_OCC_RETRY_COUNT; i++)); do
    if nc_occ maintenance:mode --on >/dev/null 2>&1; then
      if wait_for_maintenance_state "true"; then
        log "Nextcloud: maintenance mode confirmed ON"
        return 0
      fi
    fi
    sleep "${NC_OCC_RETRY_SLEEP}"
  done

  # Continue with backup flow anyway; stack stop still gives a consistent cold backup.
  log "WARNING: Nextcloud maintenance mode could not be confirmed ON before stop; continuing."
}

stack_post_start() {
  local i

  # Wait for app/bootstrap readiness, then disable maintenance mode.
  # Immediate --off often fails while DB/app is still starting.
  log "Nextcloud: waiting to disable maintenance mode after startup"
  for ((i = 1; i <= NC_OCC_RETRY_COUNT; i++)); do
    if nc_occ maintenance:mode --off >/dev/null 2>&1; then
      if wait_for_maintenance_state "false"; then
        log "Nextcloud: maintenance mode confirmed OFF"
        return 0
      fi
    fi
    sleep "${NC_OCC_RETRY_SLEEP}"
  done

  log "WARNING: Could not disable Nextcloud maintenance mode after startup; manual check required."
}

stack_verify() {
  # Quick HTTP check if you have a local URL; replace as you like.
  # curl -fsS https://nextcloud.yourdomain/ >/dev/null || true
  :
}
