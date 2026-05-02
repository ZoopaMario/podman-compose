STACK_NAME="nginx"
UNIT="nginx-stack.service"
PROJECT_LABEL="nginx"

DUPLICATI_JOBS=(
  "Nginx -> Remote"
  "Nginx -> Local"
)

# Reverse proxy must always be running
RESTORE_POLICY="always"

stack_verify() {
  :
}
