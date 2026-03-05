#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds bash tee
init_validation_env
begin_script_log "validate_vps_protocols"

SUMMARY_FILE="${PROFILE_OUTPUT_DIR%/}/validation_master_summary.txt"
: > "${SUMMARY_FILE}"

run_protocol() {
  local name="$1"
  local script_path="$2"
  local token_var="${3:-AUTH_TOKEN}"
  local auth_token="${!token_var:-${AUTH_TOKEN:-}}"

  printf '%b[MASTER] Running %s validation%b\n' "${SW_YELLOW}" "${name}" "${SW_RESET}" | tee -a "${SUMMARY_FILE}"
  if AUTH_TOKEN="${auth_token}" "${script_path}"; then
    printf '%b[MASTER] %s - PASS%b\n' "${SW_GREEN}" "${name}" "${SW_RESET}" | tee -a "${SUMMARY_FILE}"
    return 0
  fi

  printf '%b[MASTER] %s - FAIL%b\n' "${SW_RED}" "${name}" "${SW_RESET}" | tee -a "${SUMMARY_FILE}"
  return 1
}

failures=0

if ! run_protocol "WireGuard" "${ROOT_DIR}/tools/validation/validate_vpn_wireguard.sh" "AUTH_TOKEN_WIREGUARD"; then
  failures=$((failures + 1))
fi
if ! run_protocol "OpenVPN" "${ROOT_DIR}/tools/validation/validate_vpn_openvpn.sh" "AUTH_TOKEN_OPENVPN"; then
  failures=$((failures + 1))
fi
if ! run_protocol "IKEv2" "${ROOT_DIR}/tools/validation/validate_vpn_ikev2.sh" "AUTH_TOKEN_IKEV2"; then
  failures=$((failures + 1))
fi

if [[ "${failures}" -eq 0 ]]; then
  printf '%b[MASTER] Overall Data Plane Status - PASS%b\n' "${SW_GREEN}" "${SW_RESET}" | tee -a "${SUMMARY_FILE}"
  exit 0
fi

printf '%b[MASTER] Overall Data Plane Status - FAIL (%s protocol checks failed)%b\n' "${SW_RED}" "${failures}" "${SW_RESET}" | tee -a "${SUMMARY_FILE}"
exit 1
