STACK_NAME="vaultwarden"
UNIT="vaultwarden-stack.service"
PROJECT_LABEL="vaultwarden"

DUPLICATI_JOBS=(
  "Vaultwarden -> Remote"
)

STOP_TIMEOUT=180
START_TIMEOUT=180
RESTORE_POLICY="previous"

stack_verify() {
  # Best-effort: show running containers after restore (if it was running)
  podman ps --filter "label=io.podman.compose.project=${PROJECT_LABEL}" --format '{{.Names}}' | head -n 5 || true
}
