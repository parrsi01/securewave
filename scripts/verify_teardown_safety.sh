#!/usr/bin/env bash
set -euo pipefail

if ! command -v ip >/dev/null 2>&1; then
  echo "ERROR: ip not found" >&2
  exit 2
fi
if ! command -v iptables >/dev/null 2>&1; then
  echo "ERROR: iptables not found" >&2
  exit 2
fi
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root to validate teardown safety" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
export PYTHONPATH="${repo_root}:${PYTHONPATH:-}"

declare -A CHAIN=( [wireguard]=WG_NAT [openvpn]=OVPN_NAT [ikev2]=IKEV2_NAT )
declare -A IIF=( [wireguard]=wg0 [openvpn]=tun0 [ikev2]=ipsec0 )
declare -A TABLE=( [wireguard]=100 [openvpn]=200 [ikev2]=300 )
declare -A TABLE_NAME=( [wireguard]=wireguard [openvpn]=openvpn [ikev2]=ikev2 )
declare -A MARK=( [wireguard]=0x64 [openvpn]=0xc8 [ikev2]=0x12c )

run_proto() {
  local protocol="$1"
  local action="$2"
  SECUREWAVE_PROTOCOL="${protocol}" SECUREWAVE_ACTION="${action}" python3 - <<'PY'
import os
from backend.services.wireguard_service import WireGuardService
from backend.services.openvpn_service import OpenVPNService
from backend.services.ikev2_service import IKEv2Service

protocol = os.environ["SECUREWAVE_PROTOCOL"]
action = os.environ["SECUREWAVE_ACTION"]
svc = {"wireguard": WireGuardService, "openvpn": OpenVPNService, "ikev2": IKEv2Service}[protocol]()
if action == "setup":
    svc.setup_network_state()
else:
    svc.teardown_network_state()
PY
}

count_hook() { iptables -t nat -S POSTROUTING | grep -c -- "-j ${1}$" || true; }
count_masq() { iptables -t nat -S "${1}" 2>/dev/null | grep -cE "^-A ${1} .* -j MASQUERADE$" || true; }
lookup_regex() {
  local protocol="$1"
  printf '(%s|%s)' "${TABLE[$protocol]}" "${TABLE_NAME[$protocol]}"
}
count_iif_rule() {
  local iface="$1"
  local protocol="$2"
  ip -4 rule show | grep -cE "iif ${iface} .*lookup $(lookup_regex "${protocol}")\b" || true
}
count_mark_rule() {
  local mark="$1"
  local protocol="$2"
  ip -4 rule show | grep -cE "fwmark ${mark} .*lookup $(lookup_regex "${protocol}")\b" || true
}
table_lines() { ip -4 route show table "${1}" | sed '/^$/d' | wc -l | tr -d ' '; }
setup_all() {
  for protocol in wireguard openvpn ikev2; do
    run_proto "${protocol}" setup
  done
}

restore_on_exit() {
  setup_all || true
}
trap restore_on_exit EXIT

main_default_before="$(ip -4 route show table main default | sed '/^$/d')"
failed=0

setup_all

for protocol in wireguard openvpn ikev2; do
  c="${CHAIN[$protocol]}"
  if [[ "$(count_hook "${c}")" -lt 1 || "$(count_masq "${c}")" -lt 1 ]]; then
    echo "ERROR: setup missing NAT state for ${protocol}" >&2
    failed=1
  fi
done

for target in wireguard openvpn ikev2; do
  setup_all

  declare -A before
  for other in wireguard openvpn ikev2; do
    before["${other}_hook"]="$(count_hook "${CHAIN[$other]}")"
    before["${other}_masq"]="$(count_masq "${CHAIN[$other]}")"
    before["${other}_iif"]="$(count_iif_rule "${IIF[$other]}" "${other}")"
    before["${other}_mark"]="$(count_mark_rule "${MARK[$other]}" "${other}")"
    before["${other}_table"]="$(table_lines "${TABLE[$other]}")"
  done

  run_proto "${target}" teardown
  run_proto "${target}" teardown

  if [[ "$(count_hook "${CHAIN[$target]}")" -gt "${before[${target}_hook]}" ]]; then
    echo "ERROR: teardown increased NAT hook count for ${target}" >&2
    failed=1
  fi
  if [[ "$(count_masq "${CHAIN[$target]}")" -gt "${before[${target}_masq]}" ]]; then
    echo "ERROR: teardown increased NAT MASQUERADE count for ${target}" >&2
    failed=1
  fi
  if [[ "$(count_iif_rule "${IIF[$target]}" "${target}")" -gt "${before[${target}_iif]}" ]]; then
    echo "ERROR: teardown increased iif rule count for ${target}" >&2
    failed=1
  fi
  if [[ "$(count_mark_rule "${MARK[$target]}" "${target}")" -gt "${before[${target}_mark]}" ]]; then
    echo "ERROR: teardown increased fwmark rule count for ${target}" >&2
    failed=1
  fi
  if [[ "$(table_lines "${TABLE[$target]}")" -gt "${before[${target}_table]}" ]]; then
    echo "ERROR: teardown increased routes in table ${TABLE[$target]}" >&2
    failed=1
  fi

  for other in wireguard openvpn ikev2; do
    [[ "${other}" == "${target}" ]] && continue
    if [[ "$(count_hook "${CHAIN[$other]}")" -ne "${before[${other}_hook]}" ]]; then
      echo "ERROR: ${target} teardown removed ${other} hook" >&2
      failed=1
    fi
    if [[ "$(count_masq "${CHAIN[$other]}")" -ne "${before[${other}_masq]}" ]]; then
      echo "ERROR: ${target} teardown removed ${other} MASQUERADE" >&2
      failed=1
    fi
    if [[ "$(count_iif_rule "${IIF[$other]}" "${other}")" -ne "${before[${other}_iif]}" ]]; then
      echo "ERROR: ${target} teardown removed ${other} iif rule" >&2
      failed=1
    fi
    if [[ "$(count_mark_rule "${MARK[$other]}" "${other}")" -ne "${before[${other}_mark]}" ]]; then
      echo "ERROR: ${target} teardown removed ${other} fwmark rule" >&2
      failed=1
    fi
    if [[ "$(table_lines "${TABLE[$other]}")" -ne "${before[${other}_table]}" ]]; then
      echo "ERROR: ${target} teardown changed table ${TABLE[$other]}" >&2
      failed=1
    fi
  done

  if [[ "$(ip -4 route show table main default | sed '/^$/d')" != "${main_default_before}" ]]; then
    echo "ERROR: global default route drift detected after ${target} teardown" >&2
    failed=1
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  echo "Teardown safety verification: FAILED" >&2
  exit 1
fi

echo "Teardown safety verification: OK"
