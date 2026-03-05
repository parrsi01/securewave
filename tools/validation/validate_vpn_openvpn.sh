#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds curl python3 ip ss openvpn ping awk grep tee hostname
init_validation_env
init_protocol_context "openvpn"

OPENVPN_SERVER_ID="${OPENVPN_SERVER_ID:-}"
OVPN_NAMESPACE="swv-ovpn-ns"
OVPN_HOST_VETH="swv-ovpn-veth0"
OVPN_NS_VETH="swv-ovpn-veth1"
OVPN_HOST_CIDR="198.19.0.5/30"
OVPN_NS_CIDR="198.19.0.6/30"
OVPN_RUNTIME_CONF="/tmp/swvovpn.conf"
OVPN_RUNTIME_PID="/tmp/swvovpn.pid"
OVPN_RUNTIME_LOG="/tmp/securewave_validate_openvpn_client_runtime.log"
OVPN_AUTH_FILE="/tmp/swvovpn.auth"
OVPN_TUN_DEV=""
OVPN_CLEANUP_DONE=0

STEP1_FILE="${PROTOCOL_OUTPUT_DIR}/step1_daemon_presence.txt"
STEP2_FILE="${PROTOCOL_OUTPUT_DIR}/step2_port_listening.txt"
STEP3_FILE="${PROTOCOL_OUTPUT_DIR}/step3_firewall_nat.txt"
STEP4_REQ="${PROTOCOL_OUTPUT_DIR}/step4_profile_request.json"
STEP4_RESP="${PROTOCOL_OUTPUT_DIR}/step4_profile_response.json"
STEP4_CONF="${PROTOCOL_OUTPUT_DIR}/step4_openvpn_profile.conf"
STEP5_FILE="${PROTOCOL_OUTPUT_DIR}/step5_client_connect.txt"
STEP6_FILE="${PROTOCOL_OUTPUT_DIR}/step6_reachability.txt"
STEP7_FILE="${PROTOCOL_OUTPUT_DIR}/step7_traffic.txt"
STEP8_FILE="${PROTOCOL_OUTPUT_DIR}/step8_stability.txt"
STEP9_FILE="${PROTOCOL_OUTPUT_DIR}/step9_cleanup.txt"

cleanup_openvpn() {
  if [[ "${OVPN_CLEANUP_DONE}" -eq 0 ]]; then
    if [[ -f "${OVPN_RUNTIME_PID}" ]]; then
      kill "$(cat "${OVPN_RUNTIME_PID}")" >/dev/null 2>&1 || true
    fi
    rm -f "${OVPN_RUNTIME_PID}" "${OVPN_RUNTIME_CONF}" "${OVPN_AUTH_FILE}" >/dev/null 2>&1 || true
    delete_namespace "${OVPN_NAMESPACE}" "${OVPN_HOST_VETH}"
  fi
}
trap cleanup_openvpn EXIT

if systemctl status openvpn-server@server --no-pager --lines=20 >"${STEP1_FILE}" 2>&1; then
  step_pass 1 "Daemon Presence"
else
  step_fail 1 "Daemon Presence" "${STEP1_FILE}"
fi

if ss -tulnp | grep -F ':1194 ' >"${STEP2_FILE}" 2>&1; then
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

if request_profile_with_recovery "openvpn" "${OPENVPN_SERVER_ID}" "${STEP4_REQ}" "${STEP4_RESP}" && json_get "${STEP4_RESP}" "profile.ovpn_config" > "${STEP4_CONF}"; then
  remote_host="$(awk '/^remote / {print $2; exit}' "${STEP4_CONF}")"
  remote_port="$(awk '/^remote / {print $3; exit}' "${STEP4_CONF}")"
  cp "${STEP4_CONF}" "${OVPN_RUNTIME_CONF}"
  if grep -Fx 'auth-user-pass' "${OVPN_RUNTIME_CONF}" >/dev/null 2>&1; then
    ovpn_auth_method="$(json_get "${STEP4_RESP}" "profile.auth_method" 2>/dev/null || true)"
    ovpn_username="$(json_get "${STEP4_RESP}" "profile.username" 2>/dev/null || true)"
    ovpn_pass="$(json_get "${STEP4_RESP}" "profile.password" 2>/dev/null || true)"
    if [[ "${ovpn_auth_method}" != "userpass" || -z "${ovpn_username}" || -z "${ovpn_pass}" ]]; then
      step_fail 4 "Profile Generation" "${STEP4_RESP}"
    fi
    printf '%s\n%s\n' "${ovpn_username}" "${ovpn_pass}" > "${OVPN_AUTH_FILE}"
    chmod 600 "${OVPN_AUTH_FILE}"
    sed "s#^auth-user-pass\$#auth-user-pass ${OVPN_AUTH_FILE}#" "${OVPN_RUNTIME_CONF}" > "${OVPN_RUNTIME_CONF}.tmp"
    mv "${OVPN_RUNTIME_CONF}.tmp" "${OVPN_RUNTIME_CONF}"
  fi
  if ! grep -Fx 'float' "${OVPN_RUNTIME_CONF}" >/dev/null 2>&1; then
    printf 'float\n' >> "${OVPN_RUNTIME_CONF}"
  fi
  if host_matches_server_ip "${remote_host}" && [[ "${remote_port}" == "1194" ]]; then
    step_pass 4 "Profile Generation"
  else
    step_fail 4 "Profile Generation" "${STEP4_CONF}"
  fi
else
  step_fail 4 "Profile Generation" "${STEP4_RESP}"
fi

setup_namespace "${OVPN_NAMESPACE}" "${OVPN_HOST_VETH}" "${OVPN_NS_VETH}" "${OVPN_HOST_CIDR}" "${OVPN_NS_CIDR}"
if capture_in_namespace "${OVPN_NAMESPACE}" "set -euo pipefail; if [[ -f '${OVPN_RUNTIME_PID}' ]]; then kill \$(cat '${OVPN_RUNTIME_PID}') >/dev/null 2>&1 || true; fi; openvpn --config '${OVPN_RUNTIME_CONF}' --daemon --writepid '${OVPN_RUNTIME_PID}' --log '${OVPN_RUNTIME_LOG}'; sleep 8; test -s '${OVPN_RUNTIME_PID}'; pid=\$(cat '${OVPN_RUNTIME_PID}'); kill -0 \"\${pid}\"; ip -o link show | grep -E 'tun[0-9]+'" "${STEP5_FILE}"; then
  OVPN_TUN_DEV="$(grep -oE 'tun[0-9]+' "${STEP5_FILE}" | head -n 1)"
  if [[ -z "${OVPN_TUN_DEV}" ]]; then
    step_fail 5 "Client Connect" "${STEP5_FILE}"
  fi
  step_pass 5 "Client Connect"
else
  step_fail 5 "Client Connect" "${STEP5_FILE}"
fi

if capture_in_namespace "${OVPN_NAMESPACE}" "set -euo pipefail; ip route show; ping -c 2 -W 3 8.8.8.8 || true; public_ip=\$(curl -4fsS --max-time 15 '${PUBLIC_IP_CHECK_URL}' 2>/dev/null || curl -4ksS --max-time 15 https://1.1.1.1/cdn-cgi/trace | awk -F= '/^ip=/{print \$2; exit}'); printf 'PUBLIC_IP=%s\n' \"\${public_ip}\"; [[ -n \"\${public_ip}\" ]]; [[ \"\${public_ip}\" == '${SERVER_PUBLIC_IP}' ]]" "${STEP6_FILE}"; then
  step_pass 6 "Reachability Test"
else
  step_fail 6 "Reachability Test" "${STEP6_FILE}"
fi

if capture_in_namespace "${OVPN_NAMESPACE}" "set -euo pipefail; bytes=\$(curl -4fsS -o /tmp/securewave_ovpn_http.out -w '%{size_download}' https://example.com 2>/dev/null || curl -4ksS -o /tmp/securewave_ovpn_http.out -w '%{size_download}' https://1.1.1.1/cdn-cgi/trace); printf 'BYTES=%s\n' \"\${bytes}\"; [[ \"\${bytes}\" -gt 0 ]]; ping -c 5 -W 3 8.8.8.8 >/dev/null || true; rm -f /tmp/securewave_ovpn_http.out" "${STEP7_FILE}"; then
  step_pass 7 "Traffic Validation"
else
  step_fail 7 "Traffic Validation" "${STEP7_FILE}"
fi

if capture_in_namespace "${OVPN_NAMESPACE}" "set -euo pipefail; sleep 3; pid=\$(cat '${OVPN_RUNTIME_PID}'); kill -0 \"\${pid}\"; ip -o link show | grep -F '${OVPN_TUN_DEV}'; curl -4fsS --max-time 15 '${PUBLIC_IP_CHECK_URL}' >/dev/null 2>&1 || curl -4ksS --max-time 15 https://1.1.1.1/cdn-cgi/trace >/dev/null" "${STEP8_FILE}"; then
  step_pass 8 "Stability Test"
else
  step_fail 8 "Stability Test" "${STEP8_FILE}"
fi

if {
  if [[ -f "${OVPN_RUNTIME_PID}" ]]; then
    kill "$(cat "${OVPN_RUNTIME_PID}")" >/dev/null 2>&1 || true
  fi
  rm -f "${OVPN_RUNTIME_PID}" "${OVPN_RUNTIME_CONF}"
  sleep 3
  if [[ -n "${OVPN_TUN_DEV}" ]] && exec_in_namespace "${OVPN_NAMESPACE}" "ip -o link show | grep -F '${OVPN_TUN_DEV}'" >/dev/null 2>&1; then
    exit 1
  fi
  delete_namespace "${OVPN_NAMESPACE}" "${OVPN_HOST_VETH}"
  if namespace_exists "${OVPN_NAMESPACE}"; then
    exit 1
  fi
} >"${STEP9_FILE}" 2>&1; then
  OVPN_CLEANUP_DONE=1
  step_pass 9 "Cleanup"
else
  step_fail 9 "Cleanup" "${STEP9_FILE}"
fi

log_line "OpenVPN validation completed successfully"
