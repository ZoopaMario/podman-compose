STACK_NAME="duplicati"
UNIT="duplicati-stack.service"
PROJECT_LABEL="duplicati"

DUPLICATI_JOBS=(
  "Duplicati -> Remote"
  "Duplicati -> Local"
)

# Duplicati must be online to perform its own backup.
SKIP_STOP="yes"
RESTORE_POLICY="always"

stack_verify() {
  :
}
