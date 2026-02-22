#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
backup_src="${repo_root}/duplicati/bin/backup"

if [[ ! -f "${backup_src}" ]]; then
  echo "Missing backup script: ${backup_src}" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

test_root="${workdir}/repo"
mkdir -p "${test_root}/duplicati/bin" "${test_root}/duplicati/stacks" "${test_root}/stubs" "${test_root}/state" "${test_root}/runtime"
cp "${backup_src}" "${test_root}/duplicati/bin/backup"
chmod +x "${test_root}/duplicati/bin/backup"

cat > "${test_root}/stubs/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-n" ]]; then
  shift
fi
exec "$@"
EOF

cat > "${test_root}/stubs/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 ]]; then
  exit 1
fi
shift
exec "$@"
EOF

cat > "${test_root}/stubs/flock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FLOCK_FAIL:-0}" == "1" ]]; then
  exit 1
fi
exit 0
EOF

cat > "${test_root}/stubs/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${test_root}/stubs/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${TEST_STATE_DIR:?}"
trace="${TEST_TRACE_FILE:?}"
echo "systemctl $*" >> "${trace}"

if [[ "${1:-}" == "--user" ]]; then
  shift
fi

cmd="${1:-}"
unit="${2:-}"

unit_file="${state_dir}/unit.${unit}"
project="$(echo "${unit}" | sed -E 's/-stack\.service$//')"
project_file="${state_dir}/project.${project}"

case "${cmd}" in
  is-active)
    if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" ]]; then
      unit="${3:-}"
      unit_file="${state_dir}/unit.${unit}"
    fi
    if [[ -f "${unit_file}" ]]; then
      cat "${unit_file}"
    else
      echo "inactive"
    fi
    ;;
  stop)
    echo "inactive" > "${unit_file}"
    echo "0" > "${project_file}"
    ;;
  start)
    echo "active" > "${unit_file}"
    echo "1" > "${project_file}"
    ;;
  *)
    ;;
esac
EOF

cat > "${test_root}/stubs/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${TEST_STATE_DIR:?}"
trace="${TEST_TRACE_FILE:?}"
echo "podman $*" >> "${trace}"

if [[ "${1:-}" == "ps" ]]; then
  if [[ "${2:-}" == "--format" ]]; then
    if [[ "${PODMAN_DUPLICATI_RUNNING:-1}" == "1" ]]; then
      echo "duplicati"
    fi
    exit 0
  fi

  if [[ "${2:-}" == "--filter" ]]; then
    label="${3:-}"
    project="${label#label=io.podman.compose.project=}"
    val="0"
    if [[ -f "${state_dir}/project.${project}" ]]; then
      val="$(cat "${state_dir}/project.${project}")"
    fi
    if [[ "${val}" == "1" ]]; then
      echo "cid-${project}"
    fi
    exit 0
  fi
fi

if [[ "${1:-}" == "exec" ]]; then
  shift
  container="${1:-}"
  shift
  if [[ "${container}" != "${DUPLICATI_CONTAINER:-duplicati}" ]]; then
    exit 1
  fi
  util="${1:-}"
  shift
  if [[ "${util}" != "duplicati-server-util" ]]; then
    exit 1
  fi
  cmd="${1:-}"
  shift || true

  case "${cmd}" in
    list-backups)
      echo "${DUPLICATI_LIST_BACKUPS:-Test Job ID: 1}"
      ;;
    status)
      echo "${DUPLICATI_STATUS_OUTPUT:-Active task: None}"
      ;;
    run)
      if [[ "${1:-}" == "--help" ]]; then
        if [[ "${DUPLICATI_SUPPORTS_WAIT:-0}" == "1" ]]; then
          echo "usage: run [--wait]"
        else
          echo "usage: run"
        fi
        exit 0
      fi
      job="${1:-}"
      if [[ "${2:-}" == "--wait" ]]; then
        echo "run waited ${job}"
        exit 0
      fi
      echo "Running backup ${job} (ID: ${DUPLICATI_RUN_ID:-1})"
      exit "${DUPLICATI_RUN_RC:-0}"
      ;;
    *)
      ;;
  esac
fi
EOF

chmod +x "${test_root}/stubs/"*

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if ! grep -Fq "${needle}" <<< "${haystack}"; then
    echo "FAIL: ${msg}" >&2
    echo "Expected to find: ${needle}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if ! grep -Fq "${needle}" "${file}"; then
    echo "FAIL: ${msg}" >&2
    echo "Expected file ${file} to contain: ${needle}" >&2
    exit 1
  fi
}

run_backup() {
  local state_dir="$1"
  local trace_file="$2"
  shift 2
  (
    cd "${test_root}"
    PATH="${test_root}/stubs:${PATH}" \
    TEST_STATE_DIR="${state_dir}" \
    TEST_TRACE_FILE="${trace_file}" \
    XDG_RUNTIME_DIR="${test_root}/runtime" \
    DUPLICATI_WAIT_TIMEOUT=1 \
    DUPLICATI_RUN_TIMEOUT=1 \
    PODMAN_CMD="sudo -n podman" \
    PODMAN_STACK_CMD="podman" \
    ./duplicati/bin/backup "$@"
  )
}

new_case() {
  local name="$1"
  local dir="${workdir}/${name}"
  mkdir -p "${dir}/state"
  : > "${dir}/trace.log"
  echo "${dir}"
}

write_stack() {
  local name="$1"
  local body="$2"
  printf '%s\n' "${body}" > "${test_root}/duplicati/stacks/${name}.sh"
}

case_dir="$(new_case "list")"
write_stack "alpha" $'STACK_NAME="alpha"\nUNIT="alpha-stack.service"\nPROJECT_LABEL="alpha"\nDUPLICATI_JOBS=("A")'
write_stack "beta" $'STACK_NAME="beta"\nUNIT="beta-stack.service"\nPROJECT_LABEL="beta"\nDUPLICATI_JOBS=("B")'
out="$(run_backup "${case_dir}/state" "${case_dir}/trace.log" list)"
assert_contains "${out}" "alpha" "list should include alpha"
assert_contains "${out}" "beta" "list should include beta"

case_dir="$(new_case "normalize")"
write_stack "vaultwarden" $'STACK_NAME="vaultwarden"\nUNIT="vaultwarden-stack.service"\nPROJECT_LABEL="vaultwarden"\nDUPLICATI_JOBS=("Vault Job")\nRESTORE_POLICY="always"'
echo "active" > "${case_dir}/state/unit.vaultwarden-stack.service"
echo "1" > "${case_dir}/state/project.vaultwarden"
run_backup "${case_dir}/state" "${case_dir}/trace.log" vaultwarden-stack.service >/dev/null
assert_file_contains "${case_dir}/trace.log" "systemctl --user stop vaultwarden-stack.service" "normalized unit should be stopped"
assert_file_contains "${case_dir}/trace.log" "systemctl --user start vaultwarden-stack.service" "always policy should start stack"

case_dir="$(new_case "missing-stack")"
set +e
out="$(run_backup "${case_dir}/state" "${case_dir}/trace.log" does-not-exist 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "FAIL: missing stack should fail" >&2
  exit 1
fi
assert_contains "${out}" "No stack config" "missing stack error must be clear"

case_dir="$(new_case "empty-jobs")"
write_stack "emptyjobs" $'STACK_NAME="emptyjobs"\nUNIT="emptyjobs-stack.service"\nPROJECT_LABEL="emptyjobs"\nDUPLICATI_JOBS=()'
set +e
out="$(run_backup "${case_dir}/state" "${case_dir}/trace.log" emptyjobs 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "FAIL: empty jobs should fail" >&2
  exit 1
fi
assert_contains "${out}" "has no DUPLICATI_JOBS configured" "empty jobs should be rejected"

case_dir="$(new_case "invalid-restore-policy")"
write_stack "badpolicy" $'STACK_NAME="badpolicy"\nUNIT="badpolicy-stack.service"\nPROJECT_LABEL="badpolicy"\nDUPLICATI_JOBS=("Bad")\nRESTORE_POLICY="sometimes"'
set +e
out="$(run_backup "${case_dir}/state" "${case_dir}/trace.log" badpolicy 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "FAIL: invalid restore policy should fail" >&2
  exit 1
fi
assert_contains "${out}" "Invalid RESTORE_POLICY" "restore policy validation should fail"

case_dir="$(new_case "previous-policy-idle")"
write_stack "idle" $'STACK_NAME="idle"\nUNIT="idle-stack.service"\nPROJECT_LABEL="idle"\nDUPLICATI_JOBS=("Idle Job")\nRESTORE_POLICY="previous"'
echo "inactive" > "${case_dir}/state/unit.idle-stack.service"
echo "0" > "${case_dir}/state/project.idle"
run_backup "${case_dir}/state" "${case_dir}/trace.log" idle >/dev/null
if grep -Fq "systemctl --user start idle-stack.service" "${case_dir}/trace.log"; then
  echo "FAIL: previous policy should keep idle stack stopped" >&2
  exit 1
fi

case_dir="$(new_case "ondemand-freeze")"
write_stack "cryptpad" $'STACK_NAME="cryptpad"\nUNIT="cryptpad-stack.service"\nPROJECT_LABEL="cryptpad"\nDUPLICATI_JOBS=("Crypt Job")\nRESTORE_POLICY="previous"\nFREEZE_ONDEMAND="yes"\nONDEMAND_SOCKET="zoopa-ondemand@cryptpad.socket"\nONDEMAND_SERVICE="zoopa-ondemand@cryptpad.service"'
echo "inactive" > "${case_dir}/state/unit.cryptpad-stack.service"
echo "0" > "${case_dir}/state/project.cryptpad"
echo "active" > "${case_dir}/state/unit.zoopa-ondemand@cryptpad.socket"
run_backup "${case_dir}/state" "${case_dir}/trace.log" cryptpad >/dev/null
assert_file_contains "${case_dir}/trace.log" "systemctl --user stop zoopa-ondemand@cryptpad.socket" "ondemand socket should be frozen"
assert_file_contains "${case_dir}/trace.log" "systemctl --user start zoopa-ondemand@cryptpad.socket" "ondemand socket should be restored"

echo "backup_contract_tests: all checks passed"
