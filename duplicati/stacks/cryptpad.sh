# Required:
STACK_NAME="cryptpad"
UNIT="cryptpad-stack.service"
PROJECT_LABEL="cryptpad"

DUPLICATI_JOBS=(
  "Cryptpad -> Remote"
)

# Optional tuning:
STOP_TIMEOUT=180
START_TIMEOUT=180

# New: restore behavior
# - previous: if CryptPad was not running before backup (typical on-demand idle), leave it stopped afterward
# - always   : always start after backup
RESTORE_POLICY="previous"

# New: on-demand freeze
# Prevents surprise activations while the stack is stopped and backup is running
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@cryptpad.socket"
ONDEMAND_SERVICE="zoopa-ondemand@cryptpad.service"

stack_verify() {
  # Best-effort: show some running containers after restore (if it was running)
  podman ps --filter "label=io.podman.compose.project=${PROJECT_LABEL}" --format '{{.Names}}' | head -n 5 || true

  # Best-effort: show socket state
  systemctl --user is-active "${ONDEMAND_SOCKET}" 2>/dev/null || true
}

