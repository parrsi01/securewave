#!/usr/bin/env bash
set -euo pipefail

if ! command -v iptables >/dev/null 2>&1; then
  echo "ERROR: iptables not found" >&2
  exit 2
fi

conflict=0
chains=(WG_NAT OVPN_NAT IKEV2_NAT)

echo "=== NAT TABLE (-S) ==="
iptables -t nat -S
echo
echo "=== NAT TABLE (-L -n -v) ==="
iptables -t nat -L -n -v
echo

for chain in "${chains[@]}"; do
  if ! iptables -t nat -S "${chain}" >/dev/null 2>&1; then
    echo "ERROR: missing chain ${chain}" >&2
    conflict=1
    continue
  fi

  hook_count="$(iptables -t nat -S POSTROUTING | grep -cE -- "-j ${chain}$" || true)"
  if [[ "${hook_count}" -lt 1 ]]; then
    echo "ERROR: missing POSTROUTING hook for ${chain}" >&2
    conflict=1
  elif [[ "${hook_count}" -gt 1 ]]; then
    echo "WARN: duplicate POSTROUTING hooks detected for ${chain} (${hook_count})"
  fi

  masq_count="$(iptables -t nat -S "${chain}" | grep -cE -- "^-A ${chain} .* -j MASQUERADE$" || true)"
  if [[ "${masq_count}" -lt 1 ]]; then
    echo "ERROR: missing MASQUERADE rule in ${chain}" >&2
    conflict=1
  elif [[ "${masq_count}" -gt 1 ]]; then
    echo "WARN: duplicate MASQUERADE rules detected for ${chain} (${masq_count})"
  fi
done

if [[ "${conflict}" -ne 0 ]]; then
  echo "NAT isolation verification: FAILED" >&2
  exit 1
fi

echo "NAT isolation verification: OK"
