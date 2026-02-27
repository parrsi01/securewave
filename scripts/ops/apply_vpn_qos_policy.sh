#!/usr/bin/env bash
set -euo pipefail

# SecureWave VPN QoS policy (Linux tc/HTB)
# - Enforces tier throughput on VPN egress interface.
# - Intended for server-side rollout on VPN nodes.
#
# Example:
#   sudo bash scripts/ops/apply_vpn_qos_policy.sh \
#     --iface wg0 \
#     --free-cidr 10.40.0.0/16 \
#     --premium-cidr 10.50.0.0/16 \
#     --free-down 25mbit \
#     --premium-down 250mbit

IFACE=""
FREE_CIDR=""
PREMIUM_CIDR=""
FREE_DOWN="25mbit"
PREMIUM_DOWN="250mbit"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface) IFACE="${2:-}"; shift 2 ;;
    --free-cidr) FREE_CIDR="${2:-}"; shift 2 ;;
    --premium-cidr) PREMIUM_CIDR="${2:-}"; shift 2 ;;
    --free-down) FREE_DOWN="${2:-}"; shift 2 ;;
    --premium-down) PREMIUM_DOWN="${2:-}"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${IFACE}" || -z "${FREE_CIDR}" || -z "${PREMIUM_CIDR}" ]]; then
  cat <<USAGE >&2
Usage: $0 --iface <wg0|tun0> --free-cidr <cidr> --premium-cidr <cidr> [--free-down <rate>] [--premium-down <rate>]
USAGE
  exit 1
fi

command -v tc >/dev/null 2>&1 || { echo "tc not installed"; exit 1; }
command -v ip >/dev/null 2>&1 || { echo "ip not installed"; exit 1; }

if ! ip link show "${IFACE}" >/dev/null 2>&1; then
  echo "Interface ${IFACE} not found" >&2
  exit 1
fi

echo "[qos] applying on iface=${IFACE} free=${FREE_CIDR}@${FREE_DOWN} premium=${PREMIUM_CIDR}@${PREMIUM_DOWN}"

# Reset existing qdisc (idempotent).
tc qdisc del dev "${IFACE}" root 2>/dev/null || true

# Root class with conservative ceiling to avoid cost spikes.
tc qdisc add dev "${IFACE}" root handle 1: htb default 30
tc class add dev "${IFACE}" parent 1: classid 1:1 htb rate "${PREMIUM_DOWN}" ceil "${PREMIUM_DOWN}"

# Premium class
tc class add dev "${IFACE}" parent 1:1 classid 1:10 htb rate "${PREMIUM_DOWN}" ceil "${PREMIUM_DOWN}" prio 0
tc qdisc add dev "${IFACE}" parent 1:10 handle 110: fq_codel

# Free class
tc class add dev "${IFACE}" parent 1:1 classid 1:20 htb rate "${FREE_DOWN}" ceil "${FREE_DOWN}" prio 1
tc qdisc add dev "${IFACE}" parent 1:20 handle 120: fq_codel

# Default catch-all class (kept near free baseline).
tc class add dev "${IFACE}" parent 1:1 classid 1:30 htb rate "${FREE_DOWN}" ceil "${FREE_DOWN}" prio 2
tc qdisc add dev "${IFACE}" parent 1:30 handle 130: fq_codel

# Match by source CIDR from VPN address space.
tc filter add dev "${IFACE}" protocol ip parent 1: prio 10 u32 \
  match ip src "${PREMIUM_CIDR}" flowid 1:10
tc filter add dev "${IFACE}" protocol ip parent 1: prio 20 u32 \
  match ip src "${FREE_CIDR}" flowid 1:20

echo "[qos] applied successfully"
tc -s class show dev "${IFACE}" | sed -n '1,120p'
