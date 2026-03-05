#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee bash install
require_root
require_hetzner_host
begin_script_log "run_securewave_ops"

run_validation=0
if [[ "${1:-}" == "--with-validation" ]]; then
  run_validation=1
fi

install -d -m 750 "${SECUREWAVE_LOG_DIR}"
install -d -m 750 "${ROOT_DIR}/tools/provisioning" "${ROOT_DIR}/tools/validation" "${ROOT_DIR}/tools/monitoring" "${ROOT_DIR}/tools/maintenance" "${ROOT_DIR}/tools/diagnostics"

log_line "Running SecureWave operational health check"
"${ROOT_DIR}/tools/monitoring/vpn_health_check.sh"

if [[ "${run_validation}" -eq 1 ]]; then
  : "${API_BASE_URL:?API_BASE_URL is required when --with-validation is used}"
  : "${AUTH_TOKEN:?AUTH_TOKEN is required when --with-validation is used}"
  export PROFILE_OUTPUT_DIR="${PROFILE_OUTPUT_DIR:-/tmp/securewave_vps_validation}"
  log_line "Running full validation suite"
  "${ROOT_DIR}/run_all_validation_tools.sh"
else
  log_line "Skipping validation suite (pass --with-validation to enable it)"
fi

log_line "Operational summary"
log_line "Health report: ${SECUREWAVE_LOG_DIR%/}/health_report.log"
log_line "Primary log: ${LOG_FILE}"
