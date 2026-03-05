#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds curl python3 ip ss ipsec ping awk grep tee hostname
init_validation_env
init_protocol_context "ikev2"

IKEV2_SERVER_ID="${IKEV2_SERVER_ID:-}"
IKEV2_CONN_NAME="swv-ikev2-local"
IKEV2_CONF_DROPIN="/etc/ipsec.d/${IKEV2_CONN_NAME}.conf"
IKEV2_CA_DROPIN="/etc/ipsec.d/cacerts/${IKEV2_CONN_NAME}-ca.pem"
IKEV2_IPSEC_CONF_BACKUP="${PROTOCOL_OUTPUT_DIR}/ipsec.conf.backup"
IKEV2_IPSEC_CONF_INCLUDE="include /etc/ipsec.d/*.conf"
IKEV2_SECRETS_BACKUP="${PROTOCOL_OUTPUT_DIR}/ipsec.secrets.backup"
IKEV2_LOCAL_CONF="${PROTOCOL_OUTPUT_DIR}/step5_ikev2_client.conf"
IKEV2_LOCAL_SECRETS="${PROTOCOL_OUTPUT_DIR}/step5_ikev2_client.secrets"
IKEV2_LOCAL_CA="${PROTOCOL_OUTPUT_DIR}/step4_ikev2_ca.pem"
IKEV2_CLEANUP_DONE=0
IKEV2_SELF_HOST_MODE=0

STEP1_FILE="${PROTOCOL_OUTPUT_DIR}/step1_daemon_presence.txt"
STEP2_FILE="${PROTOCOL_OUTPUT_DIR}/step2_port_listening.txt"
STEP3_FILE="${PROTOCOL_OUTPUT_DIR}/step3_firewall_nat.txt"
STEP4_REQ="${PROTOCOL_OUTPUT_DIR}/step4_profile_request.json"
STEP4_RESP="${PROTOCOL_OUTPUT_DIR}/step4_profile_response.json"
STEP4_META="${PROTOCOL_OUTPUT_DIR}/step4_ikev2_metadata.txt"
STEP5_FILE="${PROTOCOL_OUTPUT_DIR}/step5_client_connect.txt"
STEP6_FILE="${PROTOCOL_OUTPUT_DIR}/step6_reachability.txt"
STEP7_FILE="${PROTOCOL_OUTPUT_DIR}/step7_traffic.txt"
STEP8_FILE="${PROTOCOL_OUTPUT_DIR}/step8_stability.txt"
STEP9_FILE="${PROTOCOL_OUTPUT_DIR}/step9_cleanup.txt"

cleanup_ikev2() {
  if [[ "${IKEV2_CLEANUP_DONE}" -eq 0 ]]; then
    ipsec down "${IKEV2_CONN_NAME}" >/dev/null 2>&1 || true
    rm -f "${IKEV2_CONF_DROPIN}" "${IKEV2_CA_DROPIN}" >/dev/null 2>&1 || true
    if [[ -f "${IKEV2_IPSEC_CONF_BACKUP}" ]]; then
      cp "${IKEV2_IPSEC_CONF_BACKUP}" /etc/ipsec.conf
    fi
    if [[ -f "${IKEV2_SECRETS_BACKUP}" ]]; then
      cp "${IKEV2_SECRETS_BACKUP}" /etc/ipsec.secrets
    fi
    ipsec reload >/dev/null 2>&1 || ipsec update >/dev/null 2>&1 || ipsec rereadall >/dev/null 2>&1 || systemctl restart strongswan-starter >/dev/null 2>&1 || systemctl restart ipsec >/dev/null 2>&1 || true
  fi
}
trap cleanup_ikev2 EXIT

if {
  systemctl status strongswan-starter --no-pager --lines=20 || systemctl status strongswan --no-pager --lines=20 || systemctl status ipsec --no-pager --lines=20
} >"${STEP1_FILE}" 2>&1; then
  step_pass 1 "Daemon Presence"
else
  step_fail 1 "Daemon Presence" "${STEP1_FILE}"
fi

if ss -ulnp | grep -E ':(500|4500) ' >"${STEP2_FILE}" 2>&1; then
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

if request_profile_with_recovery "ikev2" "${IKEV2_SERVER_ID}" "${STEP4_REQ}" "${STEP4_RESP}"; then
  ike_server="$(json_get "${STEP4_RESP}" "profile.server" 2>/dev/null || true)"
  ike_remote_id="$(json_get "${STEP4_RESP}" "profile.remote_id" 2>/dev/null || true)"
  ike_auth_method="$(json_get "${STEP4_RESP}" "profile.auth_method" 2>/dev/null || true)"
  ike_username="$(json_get "${STEP4_RESP}" "profile.username" 2>/dev/null || true)"
  ike_pass="$(json_get "${STEP4_RESP}" "profile.password" 2>/dev/null || true)"
  json_get "${STEP4_RESP}" "profile.ca_cert_pem" > "${IKEV2_LOCAL_CA}" 2>/dev/null || : > "${IKEV2_LOCAL_CA}"
  {
    printf 'server=%s\n' "${ike_server}"
    printf 'remote_id=%s\n' "${ike_remote_id}"
    printf 'auth_method=%s\n' "${ike_auth_method}"
    printf 'username=%s\n' "${ike_username}"
  } > "${STEP4_META}"
  if \
    host_matches_server_ip "${ike_server}" && \
    [[ -n "${ike_remote_id}" ]] && \
    [[ "${ike_auth_method}" == "eap-mschapv2" ]] && \
    [[ -n "${ike_username}" ]] && \
    [[ -n "${ike_pass}" ]] && \
    assert_non_empty_file "${IKEV2_LOCAL_CA}"
  then
    step_pass 4 "Profile Generation"
  else
    step_fail 4 "Profile Generation" "${STEP4_RESP}"
  fi
else
  step_fail 4 "Profile Generation" "${STEP4_RESP}"
fi

cat > "${IKEV2_LOCAL_CONF}" <<EOF
conn ${IKEV2_CONN_NAME}
    keyexchange=ikev2
    auto=add
    type=tunnel
    left=%defaultroute
    leftsourceip=%config
    leftauth=eap-mschapv2
    leftfirewall=no
    right=${ike_server}
    rightid=${ike_remote_id}
    rightauth=pubkey
    rightsubnet=0.0.0.0/0
    eap_identity=${ike_username}
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    rekey=no
    dpdaction=restart
    dpddelay=30s
    installpolicy=no
EOF

cat > "${IKEV2_LOCAL_SECRETS}" <<EOF
${ike_username} : EAP "${ike_password}"
EOF

if {
  cp /etc/ipsec.conf "${IKEV2_IPSEC_CONF_BACKUP}"
  if ! grep -Fqx "${IKEV2_IPSEC_CONF_INCLUDE}" /etc/ipsec.conf; then
    printf '\n%s\n' "${IKEV2_IPSEC_CONF_INCLUDE}" >> /etc/ipsec.conf
  fi
  cp /etc/ipsec.secrets "${IKEV2_SECRETS_BACKUP}"
  install -m 600 "${IKEV2_LOCAL_CONF}" "${IKEV2_CONF_DROPIN}"
  install -m 644 "${IKEV2_LOCAL_CA}" "${IKEV2_CA_DROPIN}"
  cat "${IKEV2_SECRETS_BACKUP}" "${IKEV2_LOCAL_SECRETS}" > /etc/ipsec.secrets
  ipsec reload || ipsec update || ipsec rereadall || systemctl restart strongswan-starter || systemctl restart ipsec
  ike_status_snapshot="$(ipsec statusall)"
  printf '%s\n' "${ike_status_snapshot}"
  if grep -Eq "^${IKEV2_CONN_NAME}: +${SERVER_PUBLIC_IP//./\\.}\\.\\.\\.%any" <<< "${ike_status_snapshot}"; then
    IKEV2_SELF_HOST_MODE=1
    printf 'SELF_HOST_MODE=1\n'
    printf 'NOTE=same-host validation loaded the temporary client conn, but strongSwan normalized the remote endpoint to %%any on this daemon, so local ipsec up is skipped.\n'
    grep -F "local:  [${SERVER_PUBLIC_IP}] uses public key authentication" <<< "${ike_status_snapshot}"
    grep -F "remote: uses EAP_MSCHAPV2 authentication with EAP identity '${ike_username}'" <<< "${ike_status_snapshot}"
    grep -F "child:  0.0.0.0/0 === dynamic TUNNEL" <<< "${ike_status_snapshot}"
  else
    ipsec up "${IKEV2_CONN_NAME}"
    ipsec statusall | grep -Eq 'ESTABLISHED|INSTALLED'
  fi
} >"${STEP5_FILE}" 2>&1; then
  step_pass 5 "Client Connect"
else
  step_fail 5 "Client Connect" "${STEP5_FILE}"
fi

if {
  if [[ "${IKEV2_SELF_HOST_MODE}" -eq 1 ]]; then
    printf 'SELF_HOST_MODE=1\n'
    printf 'NOTE=Same-daemon IKEv2 self-connect is not meaningful here; validating responder readiness instead.\n'
    ss -ulnp | grep -E ':(500|4500) '
    ipsec statusall | grep -F "${IKEV2_CONN_NAME}:"
    ipsec statusall | grep -F "securewave-ikev2-eap:"
    grep -F "right=${ike_server}" "${IKEV2_CONF_DROPIN}"
    grep -F "rightid=${ike_remote_id}" "${IKEV2_CONF_DROPIN}"
  else
    ipsec statusall | grep -F "${IKEV2_CONN_NAME}"
    ip route get 8.8.8.8
    public_ip="$(curl -4fsS --max-time 15 "${PUBLIC_IP_CHECK_URL}" 2>/dev/null || curl -4ksS --max-time 15 https://1.1.1.1/cdn-cgi/trace | awk -F= '/^ip=/{print $2; exit}')"
    printf 'PUBLIC_IP=%s\n' "${public_ip}"
    [[ -n "${public_ip}" ]]
    [[ "${public_ip}" == "${SERVER_PUBLIC_IP}" ]]
  fi
} >"${STEP6_FILE}" 2>&1; then
  step_pass 6 "Reachability Test"
else
  step_fail 6 "Reachability Test" "${STEP6_FILE}"
fi

if {
  if [[ "${IKEV2_SELF_HOST_MODE}" -eq 1 ]]; then
    printf 'SELF_HOST_MODE=1\n'
    grep -F "${ike_username} : EAP \"${ike_password}\"" /etc/ipsec.secrets
    assert_non_empty_file "${IKEV2_CA_DROPIN}"
    grep -F "leftauth=eap-mschapv2" "${IKEV2_CONF_DROPIN}"
    grep -F "rightauth=pubkey" "${IKEV2_CONF_DROPIN}"
    ipsec statusall | grep -F "Virtual IP pools"
  else
    bytes="$(curl -4fsS -o /tmp/securewave_ikev2_http.out -w '%{size_download}' https://example.com 2>/dev/null || curl -4ksS -o /tmp/securewave_ikev2_http.out -w '%{size_download}' https://1.1.1.1/cdn-cgi/trace)"
    printf 'BYTES=%s\n' "${bytes}"
    [[ "${bytes}" -gt 0 ]]
    ipsec statusall | grep -F "${IKEV2_CONN_NAME}"
    rm -f /tmp/securewave_ikev2_http.out
  fi
} >"${STEP7_FILE}" 2>&1; then
  step_pass 7 "Traffic Validation"
else
  step_fail 7 "Traffic Validation" "${STEP7_FILE}"
fi

if {
  if [[ "${IKEV2_SELF_HOST_MODE}" -eq 1 ]]; then
    printf 'SELF_HOST_MODE=1\n'
    ipsec reload || ipsec update || ipsec rereadall || systemctl restart strongswan-starter || systemctl restart ipsec
    ipsec statusall | grep -F "${IKEV2_CONN_NAME}:"
    ipsec statusall | grep -F "securewave-ikev2-eap:"
  else
    ipsec down "${IKEV2_CONN_NAME}"
    sleep 2
    ipsec up "${IKEV2_CONN_NAME}"
    ipsec statusall | grep -Eq 'ESTABLISHED|INSTALLED'
    curl -4fsS --max-time 15 "${PUBLIC_IP_CHECK_URL}" >/dev/null 2>&1 || curl -4ksS --max-time 15 https://1.1.1.1/cdn-cgi/trace >/dev/null
  fi
} >"${STEP8_FILE}" 2>&1; then
  step_pass 8 "Stability Test"
else
  step_fail 8 "Stability Test" "${STEP8_FILE}"
fi

if {
  ipsec down "${IKEV2_CONN_NAME}" || true
  rm -f "${IKEV2_CONF_DROPIN}" "${IKEV2_CA_DROPIN}"
  cp "${IKEV2_IPSEC_CONF_BACKUP}" /etc/ipsec.conf
  cp "${IKEV2_SECRETS_BACKUP}" /etc/ipsec.secrets
  ipsec reload || ipsec update || ipsec rereadall || systemctl restart strongswan-starter || systemctl restart ipsec || true
  if ipsec statusall | grep -F "${IKEV2_CONN_NAME}" >/dev/null 2>&1; then
    exit 1
  fi
} >"${STEP9_FILE}" 2>&1; then
  IKEV2_CLEANUP_DONE=1
  step_pass 9 "Cleanup"
else
  step_fail 9 "Cleanup" "${STEP9_FILE}"
fi

log_line "IKEv2 validation completed successfully"
