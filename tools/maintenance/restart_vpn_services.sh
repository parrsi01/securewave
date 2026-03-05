#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee systemctl
require_root
require_hetzner_host
begin_script_log "restart_vpn_services"

restart_if_present() {
  local unit="$1"

  if unit_file_exists "${unit}"; then
    log_line "Restarting ${unit}.service"
    systemctl restart "${unit}.service"
    systemctl is-active --quiet "${unit}.service"
  fi
}

restart_if_present fail2ban
restart_if_present nftables

for unit in strongswan-starter strongswan ipsec; do
  if unit_file_exists "${unit}"; then
    restart_if_present "${unit}"
    break
  fi
done

if [[ -f /etc/wireguard/wg0.conf ]] && unit_file_exists 'wg-quick@'; then
  restart_if_present "wg-quick@wg0"
fi

if [[ -f /etc/openvpn/server/server.conf ]] && unit_file_exists 'openvpn-server@'; then
  restart_if_present "openvpn-server@server"
fi

log_line "VPN service restart pass completed"
