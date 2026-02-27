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
  echo "ERROR: run as root to validate OpenVPN connectivity" >&2
  exit 2
fi

failed=0

echo "=== OpenVPN Service Status ==="
systemctl is-active openvpn-server@securewave 2>/dev/null || true
systemctl is-active openvpn-server@server 2>/dev/null || true
echo
echo "=== OpenVPN Port Bindings ==="
ss -lunp 2>/dev/null | grep -E ':(1194|443)\b' || true
echo
echo "=== Interface tun0 ==="
ip -d link show tun0 2>/dev/null || echo "tun0 not present"
echo
echo "=== IP Rule ==="
ip -4 rule show || true
echo
echo "=== Route Table 200 ==="
ip -4 route show table 200 || true
echo
echo "=== NAT OVPN_NAT ==="
iptables -t nat -S | grep -E 'OVPN_NAT|POSTROUTING' || true

main_default="$(ip -4 route show table main default | sed '/^$/d')"
if [[ -z "${main_default}" ]]; then
  echo "ERROR: missing main default route" >&2
  failed=1
fi
if printf '%s\n' "${main_default}" | grep -qE '\bdev tun0\b'; then
  echo "ERROR: global default route points to tun0" >&2
  failed=1
fi

if ! ip -4 rule show | grep -Eq 'fwmark 0xc8.*lookup (200|openvpn)\b'; then
  echo "ERROR: missing OpenVPN fwmark rule (0xc8 -> table 200/openvpn)" >&2
  failed=1
fi

ovpn_hook_count="$(iptables -t nat -S POSTROUTING | grep -cE -- '-j OVPN_NAT$' || true)"
if [[ "${ovpn_hook_count}" -lt 1 ]]; then
  echo "ERROR: missing POSTROUTING hook for OVPN_NAT" >&2
  failed=1
elif [[ "${ovpn_hook_count}" -gt 1 ]]; then
  echo "WARN: multiple POSTROUTING hooks for OVPN_NAT (${ovpn_hook_count})"
fi
ovpn_masq_count="$(iptables -t nat -S OVPN_NAT 2>/dev/null | grep -cE -- ' -j MASQUERADE$' || true)"
if [[ "${ovpn_masq_count}" -lt 1 ]]; then
  echo "ERROR: missing MASQUERADE in OVPN_NAT" >&2
  failed=1
elif [[ "${ovpn_masq_count}" -gt 1 ]]; then
  echo "WARN: multiple MASQUERADE rules in OVPN_NAT (${ovpn_masq_count})"
fi

if ip -4 route show table 200 default 2>/dev/null | grep -Eq '\bdev tun0\b'; then
  echo "ERROR: table 200 default route points to tun0 (recursion risk)" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "OpenVPN connectivity verification: FAILED" >&2
  exit 1
fi

echo "OpenVPN connectivity verification: OK"
