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
  echo "ERROR: run as root to inspect xfrm/iptables state" >&2
  exit 2
fi

failed=0

echo "=== ip xfrm state ==="
ip xfrm state list || true
echo
echo "=== ip xfrm policy ==="
ip xfrm policy list || true
echo
echo "=== ip rule ==="
ip -4 rule show
echo
echo "=== ip route table 300 ==="
ip -4 route show table 300 || true
echo
echo "=== NAT IKEV2_NAT hooks ==="
iptables -t nat -S | grep -E 'IKEV2_NAT|POSTROUTING' || true
echo
echo "=== strongSwan status ==="
systemctl is-active strongswan 2>/dev/null || true
systemctl is-active strongswan-starter 2>/dev/null || true
systemctl is-active charon 2>/dev/null || true
journalctl -u strongswan -n 20 --no-pager 2>/dev/null || true

main_default="$(ip -4 route show table main default | sed '/^$/d')"
main_default_count="$(printf '%s\n' "${main_default}" | wc -l | tr -d ' ')"
if [[ "${main_default_count}" -ne 1 ]]; then
  echo "ERROR: expected exactly one main default route, found ${main_default_count}" >&2
  failed=1
fi
if printf '%s\n' "${main_default}" | grep -qE '\bdev ipsec0\b'; then
  echo "ERROR: global routing overwritten (main default via ipsec0)" >&2
  failed=1
fi

if ! ip -4 rule show | grep -Eq 'lookup (300|ikev2)\b'; then
  echo "ERROR: missing table 300/ikev2 rule binding" >&2
  failed=1
fi
if ! ip -4 rule show | grep -Eq 'fwmark 0x12c.*lookup (300|ikev2)\b'; then
  echo "ERROR: missing IKEv2 fwmark rule (0x12c -> table 300/ikev2)" >&2
  failed=1
fi

hook_count="$(iptables -t nat -S POSTROUTING | grep -cE -- '-j IKEV2_NAT$' || true)"
if [[ "${hook_count}" -lt 1 ]]; then
  echo "ERROR: missing POSTROUTING hook for IKEV2_NAT" >&2
  failed=1
elif [[ "${hook_count}" -gt 1 ]]; then
  echo "WARN: multiple POSTROUTING hooks for IKEV2_NAT (${hook_count})"
fi
masq_count="$(iptables -t nat -S IKEV2_NAT 2>/dev/null | grep -cE -- ' -j MASQUERADE$' || true)"
if [[ "${masq_count}" -lt 1 ]]; then
  echo "ERROR: missing MASQUERADE in IKEV2_NAT" >&2
  failed=1
elif [[ "${masq_count}" -gt 1 ]]; then
  echo "WARN: multiple MASQUERADE rules in IKEV2_NAT (${masq_count})"
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "IKEv2 coexistence verification: FAILED" >&2
  exit 1
fi

echo "IKEv2 coexistence verification: OK"
