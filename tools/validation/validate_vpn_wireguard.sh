#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds curl python3 ip ss wg wg-quick ping awk grep tee hostname tcpdump timeout
init_validation_env
init_protocol_context "wireguard"

WIREGUARD_SERVER_ID="${WIREGUARD_SERVER_ID:-}"
WG_NAMESPACE="swv-wg-ns"
WG_HOST_VETH="swv-wg-veth0"
WG_NS_VETH="swv-wg-veth1"
WG_HOST_CIDR="198.19.0.1/30"
WG_NS_CIDR="198.19.0.2/30"
WG_RUNTIME_CONF="/tmp/swvwg.conf"
WG_IFACE="swvwg"
WG_PROBE_HOST="${WG_PROBE_HOST:-8.8.8.8}"
WG_EGRESS_IFACE="$(
  ip -4 route get "${WG_PROBE_HOST}" 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "dev") {
        print $(i + 1)
        exit
      }
    }
  }'
)"
WG_EGRESS_IFACE="${WG_EGRESS_IFACE:-eth0}"
WG_CLIENT_TUNNEL_IP=""
WG_CLEANUP_DONE=0

STEP1_FILE="${PROTOCOL_OUTPUT_DIR}/step1_daemon_presence.txt"
STEP2_FILE="${PROTOCOL_OUTPUT_DIR}/step2_port_listening.txt"
STEP3_FILE="${PROTOCOL_OUTPUT_DIR}/step3_firewall_nat.txt"
STEP4_REQ="${PROTOCOL_OUTPUT_DIR}/step4_profile_request.json"
STEP4_RESP="${PROTOCOL_OUTPUT_DIR}/step4_profile_response.json"
STEP4_CONF="${PROTOCOL_OUTPUT_DIR}/step4_wireguard_profile.conf"
STEP4_RUNTIME_CONF="${PROTOCOL_OUTPUT_DIR}/step4_wireguard_runtime.conf"
STEP5_FILE="${PROTOCOL_OUTPUT_DIR}/step5_client_connect.txt"
STEP6_FILE="${PROTOCOL_OUTPUT_DIR}/step6_reachability.txt"
STEP7_FILE="${PROTOCOL_OUTPUT_DIR}/step7_traffic.txt"
STEP8_FILE="${PROTOCOL_OUTPUT_DIR}/step8_stability.txt"
STEP9_FILE="${PROTOCOL_OUTPUT_DIR}/step9_cleanup.txt"
STEP6_WG_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step6_wg0_icmp_capture.txt"
STEP6_EGRESS_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step6_${WG_EGRESS_IFACE}_icmp_capture.txt"
STEP7_WG_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step7_wg0_icmp_capture.txt"
STEP7_EGRESS_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step7_${WG_EGRESS_IFACE}_icmp_capture.txt"
STEP8_WG_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step8_wg0_icmp_capture.txt"
STEP8_EGRESS_CAPTURE="${PROTOCOL_OUTPUT_DIR}/step8_${WG_EGRESS_IFACE}_icmp_capture.txt"

cleanup_wireguard() {
  if [[ "${WG_CLEANUP_DONE}" -eq 0 ]]; then
    exec_in_namespace "${WG_NAMESPACE}" "wg-quick down '${WG_RUNTIME_CONF}'" >/dev/null 2>&1 || true
    rm -f "${WG_RUNTIME_CONF}" >/dev/null 2>&1 || true
    delete_namespace "${WG_NAMESPACE}" "${WG_HOST_VETH}"
  fi
}
trap cleanup_wireguard EXIT

capture_wireguard_path_proof() {
  local output_file="$1"
  local wg_capture_file="$2"
  local egress_capture_file="$3"
  local ping_count="${4:-1}"
  local wg_capture_pid=""
  local egress_capture_pid=""
  local ping_status=0

  : > "${wg_capture_file}"
  : > "${egress_capture_file}"

  timeout 8 tcpdump -n -i wg0 "icmp and host ${WG_PROBE_HOST}" > "${wg_capture_file}" 2>&1 &
  wg_capture_pid=$!
  timeout 8 tcpdump -n -i "${WG_EGRESS_IFACE}" "icmp and host ${WG_PROBE_HOST}" > "${egress_capture_file}" 2>&1 &
  egress_capture_pid=$!

  sleep 1
  set +e
  exec_in_namespace "${WG_NAMESPACE}" "ping -c ${ping_count} -W 3 '${WG_PROBE_HOST}'" >> "${output_file}" 2>&1
  ping_status=$?
  set -e

  wait "${wg_capture_pid}" || true
  wait "${egress_capture_pid}" || true

  {
    printf 'PING_EXIT=%s\n' "${ping_status}"
    printf '\n=== WG0_CAPTURE (%s) ===\n' "wg0"
    cat "${wg_capture_file}"
    printf '\n=== EGRESS_CAPTURE (%s) ===\n' "${WG_EGRESS_IFACE}"
    cat "${egress_capture_file}"
  } >> "${output_file}"

  grep -F "IP ${WG_CLIENT_TUNNEL_IP} > ${WG_PROBE_HOST}: ICMP echo request" "${wg_capture_file}" >/dev/null 2>&1 &&
    grep -F "IP ${WG_PROBE_HOST} > ${WG_CLIENT_TUNNEL_IP}: ICMP echo reply" "${wg_capture_file}" >/dev/null 2>&1 &&
    grep -F "IP ${SERVER_PUBLIC_IP} > ${WG_PROBE_HOST}: ICMP echo request" "${egress_capture_file}" >/dev/null 2>&1 &&
    grep -F "IP ${WG_PROBE_HOST} > ${SERVER_PUBLIC_IP}: ICMP echo reply" "${egress_capture_file}" >/dev/null 2>&1
}

if {
  ss -ulnp | grep -F ':51820 '
  systemctl is-active --quiet wg-quick@wg0 || wg show >/dev/null
  systemctl status wg-quick@wg0 --no-pager --lines=20 || true
  wg show || true
} >"${STEP1_FILE}" 2>&1; then
  step_pass 1 "Daemon Presence"
else
  step_fail 1 "Daemon Presence" "${STEP1_FILE}"
fi

if ss -ulnp | grep -F ':51820 ' >"${STEP2_FILE}" 2>&1; then
  step_pass 2 "Port Listening"
else
  step_fail 2 "Port Listening" "${STEP2_FILE}"
fi

if {
  iptables -t nat -L -n | tee /dev/stderr | grep -i MASQUERADE
  iptables -L FORWARD -n | grep -E 'ACCEPT|DROP|REJECT'
} >"${STEP3_FILE}" 2>&1; then
  step_pass 3 "Firewall / NAT Rules"
else
  step_fail 3 "Firewall / NAT Rules" "${STEP3_FILE}"
fi

if request_profile_with_recovery "wireguard" "${WIREGUARD_SERVER_ID}" "${STEP4_REQ}" "${STEP4_RESP}" && json_get "${STEP4_RESP}" "wireguard_config" > "${STEP4_CONF}"; then
  endpoint_host="$(awk -F'[ =:]+' '/^Endpoint = / {print $2; exit}' "${STEP4_CONF}")"
  endpoint_port="$(awk -F: '/^Endpoint = / {print $NF; exit}' "${STEP4_CONF}")"
  WG_CLIENT_TUNNEL_IP="$(awk -F'[ =/]+' '/^Address = / {print $2; exit}' "${STEP4_CONF}")"
  grep -vE '^DNS = ' "${STEP4_CONF}" > "${STEP4_RUNTIME_CONF}"
  cp "${STEP4_RUNTIME_CONF}" "${WG_RUNTIME_CONF}"
  if \
    host_matches_server_ip "${endpoint_host}" && \
    [[ "${endpoint_port}" == "51820" ]] && \
    [[ -n "${WG_CLIENT_TUNNEL_IP}" ]] && \
    grep -F "wg set %i fwmark 51820" "${STEP4_CONF}" >/dev/null 2>&1 && \
    grep -F "ip rule add not fwmark 51820 table 51820 priority 32764" "${STEP4_CONF}" >/dev/null 2>&1 && \
    grep -F "ip rule add table main suppress_prefixlength 0 priority 32765" "${STEP4_CONF}" >/dev/null 2>&1 && \
    grep -F "ip route flush table 51820" "${STEP4_CONF}" >/dev/null 2>&1
  then
    step_pass 4 "Profile Generation"
  else
    step_fail 4 "Profile Generation" "${STEP4_CONF}"
  fi
else
  step_fail 4 "Profile Generation" "${STEP4_RESP}"
fi

setup_namespace "${WG_NAMESPACE}" "${WG_HOST_VETH}" "${WG_NS_VETH}" "${WG_HOST_CIDR}" "${WG_NS_CIDR}"
if capture_in_namespace "${WG_NAMESPACE}" "set -euo pipefail; wg-quick down '${WG_RUNTIME_CONF}' >/dev/null 2>&1 || true; wg-quick up '${WG_RUNTIME_CONF}'; ip link show '${WG_IFACE}'; wg show '${WG_IFACE}'" "${STEP5_FILE}"; then
  step_pass 5 "Client Connect"
else
  step_fail 5 "Client Connect" "${STEP5_FILE}"
fi

if {
  exec_in_namespace "${WG_NAMESPACE}" "set -euo pipefail; wg show '${WG_IFACE}'; ip rule show; ip route show table 51820; ip route show"
  capture_wireguard_path_proof "${STEP6_FILE}" "${STEP6_WG_CAPTURE}" "${STEP6_EGRESS_CAPTURE}" 1
} >"${STEP6_FILE}" 2>&1; then
  step_pass 6 "Reachability Test"
else
  step_fail 6 "Reachability Test" "${STEP6_FILE}"
fi

if {
  wg_tx_before="$(exec_in_namespace "${WG_NAMESPACE}" "wg show '${WG_IFACE}' transfer | awk 'NR == 1 {print \$3; exit}'")"
  printf 'WG_TX_BEFORE=%s\n' "${wg_tx_before}"
  capture_wireguard_path_proof "${STEP7_FILE}" "${STEP7_WG_CAPTURE}" "${STEP7_EGRESS_CAPTURE}" 3
  wg_tx_after="$(exec_in_namespace "${WG_NAMESPACE}" "wg show '${WG_IFACE}' transfer | awk 'NR == 1 {print \$3; exit}'")"
  printf 'WG_TX_AFTER=%s\n' "${wg_tx_after}"
  [[ "${wg_tx_after}" =~ ^[0-9]+$ ]]
  [[ "${wg_tx_before}" =~ ^[0-9]+$ ]]
  [[ "${wg_tx_after}" -gt "${wg_tx_before}" ]]
} >"${STEP7_FILE}" 2>&1; then
  step_pass 7 "Traffic Validation"
else
  step_fail 7 "Traffic Validation" "${STEP7_FILE}"
fi

if {
  exec_in_namespace "${WG_NAMESPACE}" "set -euo pipefail; wg-quick down '${WG_RUNTIME_CONF}' >/dev/null 2>&1 || true; sleep 2; wg-quick up '${WG_RUNTIME_CONF}'; wg show '${WG_IFACE}'; ip rule show; ip route show table 51820; ip route show"
  capture_wireguard_path_proof "${STEP8_FILE}" "${STEP8_WG_CAPTURE}" "${STEP8_EGRESS_CAPTURE}" 1
} >"${STEP8_FILE}" 2>&1; then
  step_pass 8 "Stability Test"
else
  step_fail 8 "Stability Test" "${STEP8_FILE}"
fi

if {
  exec_in_namespace "${WG_NAMESPACE}" "set -euo pipefail; wg-quick down '${WG_RUNTIME_CONF}' || true"
  if exec_in_namespace "${WG_NAMESPACE}" "ip link show '${WG_IFACE}'" >/dev/null 2>&1; then
    exit 1
  fi
  delete_namespace "${WG_NAMESPACE}" "${WG_HOST_VETH}"
  if namespace_exists "${WG_NAMESPACE}"; then
    exit 1
  fi
  rm -f "${WG_RUNTIME_CONF}"
} >"${STEP9_FILE}" 2>&1; then
  WG_CLEANUP_DONE=1
  step_pass 9 "Cleanup"
else
  step_fail 9 "Cleanup" "${STEP9_FILE}"
fi

log_line "WireGuard validation completed successfully"
