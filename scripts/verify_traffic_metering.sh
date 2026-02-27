#!/usr/bin/env bash
set -euo pipefail

failed=0
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
export PYTHONPATH="${repo_root}:${PYTHONPATH:-}"

print_iface() {
  local iface="$1"
  local rx="/sys/class/net/${iface}/statistics/rx_bytes"
  local tx="/sys/class/net/${iface}/statistics/tx_bytes"
  if ip link show dev "${iface}" >/dev/null 2>&1; then
    if [[ ! -f "${rx}" || ! -f "${tx}" ]]; then
      echo "ERROR: missing counters for ${iface}" >&2
      failed=1
      return
    fi
    echo "${iface}: rx_bytes=$(cat "${rx}") tx_bytes=$(cat "${tx}")"
  else
    echo "${iface}: not present"
  fi
}

echo "=== Interface Counters ==="
print_iface wg0
print_iface tun0

sim_iface="lo"
if ip link show dev wg0 >/dev/null 2>&1; then
  sim_iface="wg0"
elif ip link show dev tun0 >/dev/null 2>&1; then
  sim_iface="tun0"
fi

echo
echo "=== Metering start/stop simulation ==="
meter_json="$(SECUREWAVE_SIM_IFACE="${sim_iface}" python3 - <<'PY'
import json, os
from backend.services.traffic_manager import get_traffic_manager

mgr = get_traffic_manager()
start = mgr.start_meter(user_id=999001, protocol="wireguard", session_id="verify-meter", iface_hint=os.environ["SECUREWAVE_SIM_IFACE"])
stop = mgr.stop_meter(start["session_id"])
print(json.dumps({"start": start, "stop": stop}, sort_keys=True))
PY
)"
echo "${meter_json}"

METER_JSON="${meter_json}" python3 - <<'PY'
import json, os, sys
payload = json.loads(os.environ["METER_JSON"])
stop = payload.get("stop", {})
required = ("session_id", "user_id", "protocol", "rx_bytes", "tx_bytes", "stopped")
if not all(k in stop for k in required):
    print("ERROR: invalid metering output format", file=sys.stderr)
    sys.exit(1)
print("format_check=ok")
PY

store_file="data/usage/session_usage.jsonl"
if [[ ! -s "${store_file}" ]]; then
  echo "ERROR: missing or empty store ${store_file}" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "Traffic metering verification: FAILED" >&2
  exit 1
fi

echo "Traffic metering verification: OK"
