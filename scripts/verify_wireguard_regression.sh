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
  echo "ERROR: run as root to validate WireGuard regression" >&2
  exit 2
fi

failed=0

echo "=== WireGuard Interface ==="
ip -d link show wg0 2>/dev/null || echo "wg0 not present"
echo
echo "=== WireGuard State ==="
if command -v wg >/dev/null 2>&1; then
  wg show 2>/dev/null || true
else
  echo "wg binary not present"
fi
echo
echo "=== IP Rule ==="
ip -4 rule show || true
echo
echo "=== Route Table 100 ==="
ip -4 route show table 100 || true
echo
echo "=== NAT WG_NAT ==="
iptables -t nat -S | grep -E 'WG_NAT|POSTROUTING' || true

default_main="$(ip -4 route show table main default | sed '/^$/d')"
if [[ -z "${default_main}" ]]; then
  echo "ERROR: missing main default route" >&2
  failed=1
fi
if printf '%s\n' "${default_main}" | grep -qE '\bdev wg0\b'; then
  echo "ERROR: global default route points to wg0" >&2
  failed=1
fi

if ! ip -4 rule show | grep -Eq 'fwmark 0x64.*lookup (100|wireguard)\b'; then
  echo "ERROR: missing WireGuard fwmark rule (0x64 -> table 100/wireguard)" >&2
  failed=1
fi

wg_hook_count="$(iptables -t nat -S POSTROUTING | grep -cE -- '-j WG_NAT$' || true)"
if [[ "${wg_hook_count}" -lt 1 ]]; then
  echo "ERROR: missing POSTROUTING hook for WG_NAT" >&2
  failed=1
elif [[ "${wg_hook_count}" -gt 1 ]]; then
  echo "WARN: multiple POSTROUTING hooks for WG_NAT (${wg_hook_count})"
fi
wg_masq_count="$(iptables -t nat -S WG_NAT 2>/dev/null | grep -cE -- ' -j MASQUERADE$' || true)"
if [[ "${wg_masq_count}" -lt 1 ]]; then
  echo "ERROR: missing MASQUERADE in WG_NAT" >&2
  failed=1
elif [[ "${wg_masq_count}" -gt 1 ]]; then
  echo "WARN: multiple MASQUERADE rules in WG_NAT (${wg_masq_count})"
fi

if ip -4 route show table 100 default 2>/dev/null | grep -Eq '\bdev wg0\b'; then
  echo "ERROR: table 100 default route points to wg0 (recursion risk)" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "WireGuard regression verification: FAILED" >&2
  exit 1
fi

echo "WireGuard regression verification: OK"
