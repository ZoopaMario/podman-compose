STACK_NAME="nextcloud"
UNIT="nextcloud-stack.service"
PROJECT_LABEL="nextcloud"

DUPLICATI_JOBS=(
  "Nextcloud -> Remote"
)

# Adjust if your container name differs:
NC_APP_CONTAINER="nextcloud-app"

stack_pre_stop() {
  # Put Nextcloud into maintenance mode before stopping (best-effort).
  # If www-data user doesn't exist in your image, remove -u.
  log "Nextcloud: enabling maintenance mode (best-effort)"
  podman exec -u www-data "${NC_APP_CONTAINER}" php occ maintenance:mode --on >/dev/null 2>&1 || true
}

stack_post_start() {
  # Disable maintenance mode after start (best-effort)
  log "Nextcloud: disabling maintenance mode (best-effort)"
  podman exec -u www-data "${NC_APP_CONTAINER}" php occ maintenance:mode --off >/dev/null 2>&1 || true
}

stack_verify() {
  # Quick HTTP check if you have a local URL; replace as you like.
  # curl -fsS https://nextcloud.yourdomain/ >/dev/null || true
  :
}
