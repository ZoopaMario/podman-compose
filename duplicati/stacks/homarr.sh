STACK_NAME="homarr"
UNIT="homarr-stack.service"
PROJECT_LABEL="homarr"

DUPLICATI_JOBS=(
  "Homarr -> Remote"
  "Homarr -> Local"
)

# On-demand stack: freeze socket during backup
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@homarr.socket"
ONDEMAND_SERVICE="zoopa-ondemand@homarr.service"

# Leave stopped after backup if it was idle
RESTORE_POLICY="previous"

stack_verify() {
  :
}
