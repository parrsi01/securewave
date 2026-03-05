#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee systemctl ss iptables ip awk df grep cat
require_root
require_hetzner_host
begin_script_log "vpn_health_check"

REPORT_FILE="${SECUREWAVE_LOG_DIR%/}/health_report.log"
failures=0

write_report() {
  printf '[%s] %s\n' "$(timestamp_utc)" "$*" >> "${REPORT_FILE}"
}

check_ok() {
  write_report "PASS: $1"
  log_line "PASS: $1"
}

check_fail() {
  write_report "FAIL: $1"
  error_line "FAIL: $1"
  failures=$((failures + 1))
}

check_warn() {
  write_report "WARN: $1"
  warn_line "$1"
}

: > "${REPORT_FILE}"
write_report "SecureWave VPN health check started"

if ss -ulnp | grep -F ':51820 ' >/dev/null 2>&1; then
  check_ok "WireGuard UDP 51820 listening"
else
  check_fail "WireGuard UDP 51820 not listening"
fi

if ss -tulnp | grep -F ':1194 ' >/dev/null 2>&1; then
  check_ok "OpenVPN 1194 listening"
else
  check_fail "OpenVPN 1194 not listening"
fi

if ss -ulnp | grep -E ':(500|4500) ' >/dev/null 2>&1; then
  check_ok "IKEv2 UDP 500/4500 listening"
else
  check_fail "IKEv2 UDP 500/4500 not listening"
fi

if systemctl is-active --quiet fail2ban.service; then
  check_ok "fail2ban active"
else
  check_fail "fail2ban inactive"
fi

if systemctl is-active --quiet nftables.service; then
  check_ok "nftables active"
else
  check_fail "nftables inactive"
fi

if iptables -t nat -L -n | grep -i MASQUERADE >/dev/null 2>&1; then
  check_ok "MASQUERADE rule present"
else
  check_fail "MASQUERADE rule missing"
fi

if iptables -L FORWARD -n | grep -E 'ACCEPT|DROP|REJECT' >/dev/null 2>&1; then
  check_ok "FORWARD chain has explicit rules"
else
  check_fail "FORWARD chain missing explicit rules"
fi

if ip rule show | grep -F '51820' >/dev/null 2>&1; then
  check_ok "WireGuard policy routing rules present"
else
  check_warn "WireGuard policy routing rules missing (informational until a full-tunnel validation client is active)"
fi

load_avg="$(awk '{print $1}' /proc/loadavg)"
cpu_count="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1')"
write_report "INFO: load_average_1m=${load_avg} cpu_count=${cpu_count}"

disk_usage="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
write_report "INFO: root_disk_percent=${disk_usage}"
if [[ "${disk_usage}" -ge 90 ]]; then
  check_fail "Root filesystem usage is ${disk_usage}%"
else
  check_ok "Root filesystem usage is ${disk_usage}%"
fi

write_report "SecureWave VPN health check completed with failures=${failures}"
log_line "Health report written to ${REPORT_FILE}"

if [[ "${failures}" -ne 0 ]]; then
  exit 1
fi
