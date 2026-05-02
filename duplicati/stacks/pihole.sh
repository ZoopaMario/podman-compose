STACK_NAME="pihole"
UNIT="pihole-stack.service"
PROJECT_LABEL="pihole"

DUPLICATI_JOBS=(
  "Pi-hole -> Remote"
  "Pi-hole -> Local"
)

# DNS MUST be always running. 
# We perform a "Hot" backup because stopping Pi-hole breaks Duplicati's DNS resolution.
SKIP_STOP="yes"
RESTORE_POLICY="always"

stack_verify() {
  :
}
