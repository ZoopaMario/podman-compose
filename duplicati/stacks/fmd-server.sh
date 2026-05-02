STACK_NAME="fmd-server"
UNIT="fmd-server-stack.service"
PROJECT_LABEL="fmd-server"

DUPLICATI_JOBS=(
  "FMD-Server -> Remote"
  "FMD-Server -> Local"
)

# On-demand stack: freeze socket during backup
FREEZE_ONDEMAND="yes"
ONDEMAND_SOCKET="zoopa-ondemand@fmd-server.socket"
ONDEMAND_SERVICE="zoopa-ondemand@fmd-server.service"

# Leave stopped after backup if it was idle
RESTORE_POLICY="previous"

stack_verify() {
  :
}
