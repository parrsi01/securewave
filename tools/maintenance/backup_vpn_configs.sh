#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee tar install
require_root
require_hetzner_host
begin_script_log "backup_vpn_configs"

backup_dir="${SECUREWAVE_LOG_DIR%/}/backups"
backup_file="${backup_dir}/securewave_configs_$(timestamp_slug).tar.gz"

install -d -m 750 "${backup_dir}"

paths=()
for candidate in /etc/securewave /etc/wireguard /etc/openvpn /etc/ipsec.conf /etc/ipsec.secrets /etc/ipsec.d; do
  if [[ -e "${candidate}" ]]; then
    paths+=("${candidate}")
  fi
done

if [[ "${#paths[@]}" -eq 0 ]]; then
  error_line "No VPN configuration paths found to back up."
  exit 1
fi

tar -czf "${backup_file}" "${paths[@]}"
log_line "Backed up ${#paths[@]} configuration path(s) to ${backup_file}"
