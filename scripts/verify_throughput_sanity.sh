#!/usr/bin/env bash
set -euo pipefail

failed=0
warn=0

show_delta() {
  local iface="$1"
  local rx="/sys/class/net/${iface}/statistics/rx_bytes"
  local tx="/sys/class/net/${iface}/statistics/tx_bytes"
  if [[ ! -f "${rx}" || ! -f "${tx}" ]]; then
    echo "${iface}: not present"
    return 0
  fi
  local rx1 tx1 rx2 tx2
  rx1="$(cat "${rx}")"; tx1="$(cat "${tx}")"
  sleep 10
  rx2="$(cat "${rx}")"; tx2="$(cat "${tx}")"
  echo "${iface}: rx_delta=$((rx2-rx1)) tx_delta=$((tx2-tx1)) over 10s"
}

echo "=== Interface Deltas (10s) ==="
show_delta wg0
show_delta tun0

echo
echo "=== Routing Summary ==="
ip -4 rule show || true
ip -4 route show table main || true
for table in 100 200 300; do
  echo "--- table ${table} ---"
  ip -4 route show table "${table}" || true
done

echo
echo "=== NAT Summary ==="
iptables -t nat -S 2>/dev/null || echo "iptables nat view unavailable (need root)"
iptables -S 2>/dev/null || echo "iptables filter view unavailable (need root)"

echo
echo "=== Retransmit Signals ==="
ss -s || true
ss -ti 2>/dev/null | sed -n '1,120p' || true
if command -v netstat >/dev/null 2>&1; then
  netstat -s 2>/dev/null | grep -Ei 'retrans|segments retransmitted|fail|reset' || true
fi

echo
echo "=== MTU Heuristics ==="
main_def="$(ip -4 route show default | head -n1 || true)"
main_iface="$(awk '/^default / {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"${main_def}")"
if [[ -n "${main_iface}" && -f "/sys/class/net/${main_iface}/mtu" ]]; then
  main_mtu="$(cat "/sys/class/net/${main_iface}/mtu")"
  echo "main default iface=${main_iface} mtu=${main_mtu}"
  for t in wg0 tun0 ipsec0 xfrm0; do
    if [[ -f "/sys/class/net/${t}/mtu" ]]; then
      t_mtu="$(cat "/sys/class/net/${t}/mtu")"
      echo "${t} mtu=${t_mtu}"
      if (( t_mtu >= main_mtu )); then
        echo "WARN: ${t} mtu (${t_mtu}) >= egress mtu (${main_mtu}); MSS/fragmentation risk" >&2
        warn=1
      fi
    fi
  done
  ping -M do -s 1472 -c 2 1.1.1.1 >/dev/null 2>&1 || { echo "WARN: PMTU 1500 payload probe failed (1472)"; warn=1; }
fi

echo
echo "=== Recursion Checks ==="
if ip -4 route show table main default | grep -Eq 'dev (wg0|tun0|ipsec0|xfrm0)\b'; then
  echo "ERROR: main default route points into tunnel interface" >&2
  failed=1
fi
if ip -4 route show table 100 default 2>/dev/null | grep -Eq '\bdev wg0\b'; then
  echo "ERROR: table 100 default uses wg0 (route recursion risk)" >&2
  failed=1
fi
if ip -4 route show table 200 default 2>/dev/null | grep -Eq '\bdev tun0\b'; then
  echo "ERROR: table 200 default uses tun0 (route recursion risk)" >&2
  failed=1
fi
if ip -4 route show table 300 default 2>/dev/null | grep -Eq '\bdev (ipsec0|xfrm0)\b'; then
  echo "ERROR: table 300 default uses ipsec/xfrm iface (route recursion risk)" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "Throughput sanity verification: FAILED" >&2
  exit 1
fi
if [[ "${warn}" -ne 0 ]]; then
  echo "Throughput sanity verification: OK with warnings"
  exit 0
fi
echo "Throughput sanity verification: OK"
