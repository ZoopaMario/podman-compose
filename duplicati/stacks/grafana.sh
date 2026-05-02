STACK_NAME="grafana"
UNIT="grafana-stack.service"
PROJECT_LABEL="grafana"

DUPLICATI_JOBS=(
  "Grafana -> Remote"
  "Grafana -> Local"
)

# Cold backup is safest for Prometheus TSDB consistency
STOP_TIMEOUT=120
START_TIMEOUT=120
RESTORE_POLICY="previous"

stack_verify() {
  # Check for Grafana DB
  if [[ -f "/mnt/data/grafana/data/grafana.db" ]]; then
    log "Grafana: Internal DB found: /mnt/data/grafana/data/grafana.db"
  fi
}
