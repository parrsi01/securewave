#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

REQUIRED_ENV_VARS=(
  API_BASE_URL
  AUTH_TOKEN
  PROFILE_OUTPUT_DIR
)

REQUIRED_SCRIPTS=(
  "tools/validation/_validation_common.sh"
  "tools/validation/validate_vps_protocols.sh"
  "tools/validation/validate_vpn_wireguard.sh"
  "tools/validation/validate_vpn_openvpn.sh"
  "tools/validation/validate_vpn_ikev2.sh"
)

log_header() {
  printf '%b%s%b\n' "${SW_YELLOW}" "$1" "${SW_RESET}"
}

log_pass() {
  printf '%b%s%b\n' "${SW_GREEN}" "$1" "${SW_RESET}"
}

log_fail() {
  printf '%b%s%b\n' "${SW_RED}" "$1" "${SW_RESET}" >&2
}

require_env_vars() {
  local missing=0
  local var_name

  for var_name in "${REQUIRED_ENV_VARS[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      log_fail "[ENV] Missing required environment variable: ${var_name}"
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi

  mkdir -p "${PROFILE_OUTPUT_DIR}"
  log_pass "[ENV] Required environment variables present"
}

require_validation_scripts() {
  local missing=0
  local script_path

  for script_path in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "${ROOT_DIR}/${script_path}" ]]; then
      log_fail "[CHECK] Missing validation script: ${script_path}"
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi

  log_pass "[CHECK] Required validation scripts found"
}

main() {
  require_cmds tee
  require_root
  require_hetzner_host
  begin_script_log "run_all_validation_tools"

  log_header "[START] SecureWave single-host Hetzner validation runner"
  log_header "[WARNING] This must be run as root on the Hetzner VPN server."
  require_env_vars
  require_validation_scripts

  exec "${ROOT_DIR}/tools/validation/validate_vps_protocols.sh"
}

main "$@"
