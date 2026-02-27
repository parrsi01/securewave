#!/usr/bin/env bash
set -euo pipefail

if ! command -v ip >/dev/null 2>&1; then
  echo "ERROR: ip command not found" >&2
  exit 2
fi

conflict=0
tables=(100 200 300)
vpn_ifaces=(wg0 sw-wg tun0 ipsec0)

echo "=== IP RULES ==="
ip rule show
echo

for table in "${tables[@]}"; do
  echo "=== ROUTE TABLE ${table} ==="
  table_routes="$(ip route show table "${table}" 2>/dev/null || true)"
  if [[ -z "${table_routes}" ]]; then
    echo "ERROR: route table ${table} missing or empty" >&2
    conflict=1
  fi
  printf '%s\n' "${table_routes}"
  echo
done

main_defaults="$(ip -4 route show table main default || true)"
main_default_count="$(printf '%s\n' "${main_defaults}" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "${main_default_count}" -gt 1 ]]; then
  echo "ERROR: duplicate default routes in main table (${main_default_count})" >&2
  conflict=1
fi

main_default_dev="$(printf '%s\n' "${main_defaults}" | awk '/^default / {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
for iface in "${vpn_ifaces[@]}"; do
  if [[ "${main_default_dev:-}" == "${iface}" ]]; then
    echo "ERROR: main table default route points to VPN interface (${iface})" >&2
    conflict=1
  fi
done

for table in "${tables[@]}"; do
  table_default_lines="$(ip -4 route show table "${table}" default 2>/dev/null || true)"
  table_default_count="$(printf '%s\n' "${table_default_lines}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${table_default_count}" -eq 0 ]]; then
    echo "ERROR: missing default route in table ${table}" >&2
    conflict=1
  fi
  if [[ "${table_default_count}" -gt 1 ]]; then
    echo "ERROR: duplicate default routes in table ${table} (${table_default_count})" >&2
    conflict=1
  fi
done

fwmark_values="$(ip rule show | awk '/fwmark/ {for(i=1;i<=NF;i++) if($i=="fwmark"){print $(i+1)}}')"
if [[ -n "${fwmark_values}" ]]; then
  while IFS= read -r mark; do
    [[ -z "${mark}" ]] && continue
    mark_count="$(printf '%s\n' "${fwmark_values}" | grep -Fx -c "${mark}" || true)"
    if [[ "${mark_count}" -gt 1 ]]; then
      echo "ERROR: conflicting fwmark rule detected (${mark}, count=${mark_count})" >&2
      conflict=1
    fi
  done < <(printf '%s\n' "${fwmark_values}" | sort -u)
fi

if [[ "${conflict}" -ne 0 ]]; then
  echo "Policy routing verification: FAILED" >&2
  exit 1
fi

echo "Policy routing verification: OK"
