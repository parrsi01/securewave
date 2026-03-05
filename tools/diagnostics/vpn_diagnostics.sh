#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee uname hostnamectl ip iptables systemctl journalctl df free
require_root
require_hetzner_host
begin_script_log "vpn_diagnostics"

report_file="/tmp/securewave_diagnostics_$(timestamp_slug).log"

{
  printf '=== SecureWave Diagnostics (%s) ===\n' "$(timestamp_utc)"
  printf '\n=== Host ===\n'
  uname -a
  hostnamectl 2>/dev/null || true

  printf '\n=== WireGuard ===\n'
  wg show 2>/dev/null || true

  printf '\n=== Routing ===\n'
  ip route show
  printf '\n'
  ip rule show

  printf '\n=== Firewall ===\n'
  iptables -t nat -L -n
  printf '\n'
  iptables -L FORWARD -n

  printf '\n=== Service Status ===\n'
  systemctl status wg-quick@wg0 --no-pager --lines=25 2>/dev/null || true
  systemctl status openvpn-server@server --no-pager --lines=25 2>/dev/null || true
  systemctl status strongswan-starter --no-pager --lines=25 2>/dev/null || systemctl status strongswan --no-pager --lines=25 2>/dev/null || systemctl status ipsec --no-pager --lines=25 2>/dev/null || true
  systemctl status fail2ban --no-pager --lines=25 2>/dev/null || true

  printf '\n=== Journal Excerpts ===\n'
  journalctl -u wg-quick@wg0 -n 50 --no-pager 2>/dev/null || true
  journalctl -u openvpn-server@server -n 50 --no-pager 2>/dev/null || true
  journalctl -u strongswan-starter -n 50 --no-pager 2>/dev/null || journalctl -u strongswan -n 50 --no-pager 2>/dev/null || journalctl -u ipsec -n 50 --no-pager 2>/dev/null || true

  printf '\n=== Capacity ===\n'
  df -h
  printf '\n'
  free -h
} > "${report_file}"

log_line "Diagnostics report written to ${report_file}"
