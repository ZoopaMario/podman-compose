STACK_NAME="jellyfin"
UNIT="jellyfin-stack.service"
PROJECT_LABEL="jellyfin"

DUPLICATI_JOBS=(
  "Jellyfin -> Remote"
  "Jellyfin -> Local"
)

# Jellyfin stores config and cache locally, media on NFS.
# We'll back up config and local data, but exclude cache and media.
# Jellyfin is not on-demand.
RESTORE_POLICY="previous"
STOP_TIMEOUT=180
START_TIMEOUT=180

stack_verify() {
  # Check if Jellyfin config directory exists
  if [[ -d "/mnt/data/jellyfin/config" ]]; then
    log "Jellyfin: Config directory found: /mnt/data/jellyfin/config"
  else
    log "WARNING: Jellyfin: Config directory NOT found at expected path."
  fi
}
