#!/usr/bin/env bash
set -euo pipefail

mode="auto"
for arg in "$@"; do
  case "$arg" in
    --mode=auto|--mode=integration|--mode=full)
      mode="${arg#--mode=}"
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cap_script="${repo_root}/scripts/ci/detect_backup_capabilities.sh"

eval "$("${cap_script}")"

should_run_integration="false"
should_run_full="false"

case "${mode}" in
  integration)
    should_run_integration="true"
    ;;
  full)
    should_run_integration="true"
    should_run_full="true"
    ;;
  auto)
    should_run_integration="true"
    if [[ "${CAN_RUN_FULL_BACKUP_INTEGRATION}" == "true" ]]; then
      should_run_full="true"
    fi
    ;;
esac

if [[ "${should_run_integration}" == "true" ]]; then
  echo "Running backup integration baseline (synthetic harness)"
  "${repo_root}/scripts/tests/backup_contract_tests.sh"
fi

if [[ "${should_run_full}" != "true" ]]; then
  echo "Skipping full restore smoke: runner lacks full integration capability"
  exit 0
fi

echo "Running full restore smoke checks"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

src_dir="${scratch}/src"
bak_dir="${scratch}/backup"
restore_dir="${scratch}/restore"
mkdir -p "${src_dir}" "${bak_dir}" "${restore_dir}"

printf 'backup smoke test\n' > "${src_dir}/fixture.txt"
src_sha="$(sha256sum "${src_dir}/fixture.txt" | awk '{print $1}')"

if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "${src_dir}/fixture.db" "create table t(v text); insert into t(v) values ('ok');"
fi

tar -C "${src_dir}" -cf "${bak_dir}/snapshot.tar" .
tar -C "${restore_dir}" -xf "${bak_dir}/snapshot.tar"

restored_sha="$(sha256sum "${restore_dir}/fixture.txt" | awk '{print $1}')"
if [[ "${src_sha}" != "${restored_sha}" ]]; then
  echo "FAIL: restored file checksum mismatch" >&2
  exit 1
fi

if [[ -f "${restore_dir}/fixture.db" ]] && command -v sqlite3 >/dev/null 2>&1; then
  result="$(sqlite3 "${restore_dir}/fixture.db" "pragma integrity_check;")"
  if [[ "${result}" != "ok" ]]; then
    echo "FAIL: restored sqlite integrity check failed: ${result}" >&2
    exit 1
  fi
fi

echo "backup_integration_tests: full restore smoke passed"
