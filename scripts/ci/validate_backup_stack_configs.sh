#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
stacks_dir="${repo_root}/duplicati/stacks"

shopt -s nullglob
stack_files=("${stacks_dir}"/*.sh)
shopt -u nullglob

if [[ "${#stack_files[@]}" -eq 0 ]]; then
  echo "No stack config files found in ${stacks_dir}" >&2
  exit 1
fi

failed=0

for file in "${stack_files[@]}"; do
  echo "Validating ${file}"

  if ! bash -n "$file"; then
    failed=1
    continue
  fi

  STACK_NAME=""
  UNIT=""
  PROJECT_LABEL=""
  RESTORE_POLICY=""
  FREEZE_ONDEMAND="no"
  ONDEMAND_SOCKET=""
  DUPLICATI_JOBS=()
  log() { :; }

  # shellcheck source=/dev/null
  source "$file"

  if [[ -z "${STACK_NAME}" ]]; then
    echo "ERROR: STACK_NAME is required in ${file}" >&2
    failed=1
  fi
  if [[ -z "${UNIT}" ]]; then
    echo "ERROR: UNIT is required in ${file}" >&2
    failed=1
  fi
  if [[ -z "${PROJECT_LABEL}" ]]; then
    echo "ERROR: PROJECT_LABEL is required in ${file}" >&2
    failed=1
  fi
  if [[ "${#DUPLICATI_JOBS[@]}" -eq 0 ]]; then
    echo "ERROR: DUPLICATI_JOBS must contain at least one entry in ${file}" >&2
    failed=1
  fi

  if [[ -n "${RESTORE_POLICY}" && "${RESTORE_POLICY}" != "previous" && "${RESTORE_POLICY}" != "always" ]]; then
    echo "ERROR: RESTORE_POLICY must be previous|always in ${file}" >&2
    failed=1
  fi

  if [[ "${FREEZE_ONDEMAND}" == "yes" && -z "${ONDEMAND_SOCKET}" ]]; then
    echo "ERROR: ONDEMAND_SOCKET is required when FREEZE_ONDEMAND=yes in ${file}" >&2
    failed=1
  fi
done

exit "${failed}"
