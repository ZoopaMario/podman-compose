STACK_NAME="forgejo"
UNIT="forgejo-stack.service"
PROJECT_LABEL="forgejo"

DUPLICATI_JOBS=(
  "Forgejo -> Remote"
  "Forgejo -> Local"
)

STOP_TIMEOUT=240
START_TIMEOUT=240
RESTORE_POLICY="previous"

stack_verify() {
  # Best-effort: show running containers after restore (if it was running)
  podman ps --filter "label=io.podman.compose.project=${PROJECT_LABEL}" --format '{{.Names}}' | head -n 5 || true
}
