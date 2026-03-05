#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee find gzip mv truncate basename
require_root
require_hetzner_host
begin_script_log "rotate_logs"

rotation_suffix="$(timestamp_slug)"
retention_days="${SECUREWAVE_LOG_RETENTION_DAYS:-14}"

find "${SECUREWAVE_LOG_DIR}" -maxdepth 1 -type f -name '*.log' | while read -r log_path; do
  base_name="$(basename "${log_path}")"
  if [[ "${base_name}" == "rotate_logs.log" ]]; then
    continue
  fi
  if [[ ! -s "${log_path}" ]]; then
    continue
  fi

  archived_path="${log_path}.${rotation_suffix}"
  mv "${log_path}" "${archived_path}"
  gzip -f "${archived_path}"
  truncate -s 0 "${log_path}"
  log_line "Rotated ${base_name} -> ${archived_path}.gz"
done

find "${SECUREWAVE_LOG_DIR}" -maxdepth 1 -type f -name '*.gz' -mtime "+${retention_days}" -delete
log_line "Pruned compressed logs older than ${retention_days} days"
