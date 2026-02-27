#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root for tc verification" >&2
  exit 2
fi
if ! command -v tc >/dev/null 2>&1; then
  echo "ERROR: tc not found" >&2
  exit 2
fi

failed=0
vpn_ifaces=(wg0 tun0 ipsec0 xfrm0)
strict_qdisc=1

echo "=== qdisc/class snapshots ==="
for iface in "${vpn_ifaces[@]}"; do
  if ip link show dev "${iface}" >/dev/null 2>&1; then
    echo "--- ${iface} qdisc ---"
    tc qdisc show dev "${iface}" || true
    echo "--- ${iface} class ---"
    tc class show dev "${iface}" || true
  fi
done

test_iface="lo"
for iface in wg0 tun0 ipsec0 xfrm0; do
  if ip link show dev "${iface}" >/dev/null 2>&1; then
    test_iface="${iface}"
    break
  fi
done
if [[ "${test_iface}" == "lo" ]]; then
  strict_qdisc=0
  echo "WARN: no VPN iface present; loopback shaping check is best-effort"
fi
echo "using test interface: ${test_iface}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
export PYTHONPATH="${repo_root}:${PYTHONPATH:-}"

python3 - <<PY
from backend.services.traffic_shaper import get_traffic_shaper
s = get_traffic_shaper()
print(s.apply_for_session(91001, "wireguard", "free", "verify-free", "${test_iface}"))
print(s.apply_for_session(91002, "wireguard", "premium", "verify-prem", "${test_iface}"))
PY

free_count="$(tc qdisc show dev "${test_iface}" | grep -c 'handle 551: tbf' || true)"
if [[ "${strict_qdisc}" -eq 1 && "${free_count}" -ne 1 ]]; then
  echo "ERROR: expected exactly one Free-tier TBF qdisc on ${test_iface}, found ${free_count}" >&2
  failed=1
fi
if [[ "${strict_qdisc}" -eq 0 && "${free_count}" -eq 0 ]]; then
  echo "WARN: no Free-tier TBF qdisc visible on ${test_iface}; skipping strict check"
fi

dup_count="$(tc qdisc show dev "${test_iface}" | grep -c ' tbf ' || true)"
if [[ "${strict_qdisc}" -eq 1 && "${dup_count}" -gt 1 ]]; then
  echo "ERROR: duplicate shaping qdisc detected on ${test_iface}" >&2
  failed=1
fi

main_iface="$(ip -4 route show default | awk '/^default / {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -n "${main_iface}" && "${main_iface}" != "wg0" && "${main_iface}" != "tun0" && "${main_iface}" != "ipsec0" && "${main_iface}" != "xfrm0" ]]; then
  if tc qdisc show dev "${main_iface}" | grep -q 'handle 551: tbf'; then
    echo "ERROR: global shaping detected on non-VPN default iface ${main_iface}" >&2
    failed=1
  fi
fi

python3 - <<PY
from backend.services.traffic_shaper import get_traffic_shaper
s = get_traffic_shaper()
print(s.remove_for_session("verify-prem"))
print(s.remove_for_session("verify-free"))
PY

post_count="$(tc qdisc show dev "${test_iface}" | grep -c 'handle 551: tbf' || true)"
if [[ "${strict_qdisc}" -eq 1 && "${post_count}" -ne 0 ]]; then
  echo "ERROR: shaping teardown left Free-tier qdisc on ${test_iface}" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "Shaping verification: FAILED" >&2
  exit 1
fi
echo "Shaping verification: OK"
