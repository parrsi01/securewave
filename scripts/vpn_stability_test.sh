#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python3}"
fi

API_BASE_URL="${API_BASE_URL:-${LIVE_API_BASE_URL:-}}"
PROFILE_PATH="${VPN_PROFILE_PATH:-}"
CYCLES="${VPN_STABILITY_CYCLES:-25}"
CONNECTED_SLEEP="${VPN_STABILITY_CONNECTED_SLEEP:-10}"
DISCONNECTED_SLEEP="${VPN_STABILITY_DISCONNECTED_SLEEP:-5}"
SPLIT_TUNNEL=false
SPLIT_TUNNEL_ALLOWED_IPS="${VPN_STABILITY_ALLOWED_IPS:-10.0.0.0/8,172.16.0.0/12}"
IPERF_HOST="${VPN_STABILITY_IPERF_HOST:-}"
TCPDUMP_SECONDS="${VPN_STABILITY_TCPDUMP_SECONDS:-0}"
RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
RUN_DIR="${ROOT_DIR}/artifacts/vpn_stability/${RUN_ID}"
INTERFACE_NAME="swstb"

usage() {
  cat <<'EOF'
Usage:
  scripts/vpn_stability_test.sh --api-base-url https://host/api --profile /path/to/profile.conf [options]

Options:
  --api-base-url URL
  --profile PATH
  --cycles N
  --connected-sleep N
  --disconnected-sleep N
  --split-tunnel
  --split-tunnel-allowed-ips CIDRS
  --iperf-host HOST
  --tcpdump-seconds N
  --out-dir PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url)
      API_BASE_URL="$2"
      shift 2
      ;;
    --profile)
      PROFILE_PATH="$2"
      shift 2
      ;;
    --cycles)
      CYCLES="$2"
      shift 2
      ;;
    --connected-sleep)
      CONNECTED_SLEEP="$2"
      shift 2
      ;;
    --disconnected-sleep)
      DISCONNECTED_SLEEP="$2"
      shift 2
      ;;
    --split-tunnel)
      SPLIT_TUNNEL=true
      shift
      ;;
    --split-tunnel-allowed-ips)
      SPLIT_TUNNEL_ALLOWED_IPS="$2"
      shift 2
      ;;
    --iperf-host)
      IPERF_HOST="$2"
      shift 2
      ;;
    --tcpdump-seconds)
      TCPDUMP_SECONDS="$2"
      shift 2
      ;;
    --out-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${API_BASE_URL}" || -z "${PROFILE_PATH}" ]]; then
  usage >&2
  exit 2
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root or via sudo." >&2
  exit 2
fi

mkdir -p "${RUN_DIR}"
TMP_CONFIG="${RUN_DIR}/${INTERFACE_NAME}.conf"
META_JSON="${RUN_DIR}/render_meta.json"
RESULT_CSV="${RUN_DIR}/cycles.csv"
REPORT_MD="${RUN_DIR}/REPORT.md"

"${PYTHON_BIN}" "${ROOT_DIR}/dev_tools/sandbox/live_validation/render_test_wireguard_config.py" \
  --input "${PROFILE_PATH}" \
  --output "${TMP_CONFIG}" \
  --api-base-url "${API_BASE_URL}" \
  $(if [[ "${SPLIT_TUNNEL}" == "true" ]]; then printf '%s ' --split-tunnel; fi) \
  --split-tunnel-allowed-ips "${SPLIT_TUNNEL_ALLOWED_IPS}" \
  > "${META_JSON}"

API_HOST="$("${PYTHON_BIN}" -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("api_host") or "")' "${META_JSON}")"
API_IP="$("${PYTHON_BIN}" -c 'import json,sys; data=json.load(open(sys.argv[1])); ips=data.get("api_ips") or []; print(ips[0] if ips else "")' "${META_JSON}")"
if [[ -z "${API_IP}" && -n "${API_HOST}" ]]; then
  API_IP="$(getent ahostsv4 "${API_HOST}" | awk 'NR==1 {print $1; exit}' || true)"
fi
HEALTH_URL="${API_BASE_URL%/}/health"
BASELINE_IP="$(curl --max-time 10 -sS https://api.ipify.org || true)"

cleanup() {
  set +e
  wg-quick down "${TMP_CONFIG}" >/dev/null 2>&1 || true
  if [[ -n "${API_IP}" ]]; then
    ip route del "${API_IP}/32" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "cycle,connect_ok,handshake_ok,route_ok,api_health_http,public_ip,ip_changed,iperf_ok,tcpdump_ok" > "${RESULT_CSV}"

connect_failures=0
handshake_failures=0
route_failures=0
api_failures=0
iperf_failures=0
tcpdump_failures=0
ip_changed_count=0

for ((cycle=1; cycle<=CYCLES; cycle+=1)); do
  cycle_dir="${RUN_DIR}/cycle_${cycle}"
  mkdir -p "${cycle_dir}"

  ORIGINAL_GATEWAY="$(ip route show default 0.0.0.0/0 | awk 'NR==1 {print $3; exit}')"
  ORIGINAL_DEV="$(ip route show default 0.0.0.0/0 | awk 'NR==1 {print $5; exit}')"
  ip route > "${cycle_dir}/routes_before.txt"
  ip rule show > "${cycle_dir}/rules_before.txt"
  if [[ -n "${API_IP}" ]]; then
    ip route replace "${API_IP}/32" via "${ORIGINAL_GATEWAY}" dev "${ORIGINAL_DEV}" metric 5
    ip route get "${API_IP}" > "${cycle_dir}/route_get_before.txt" 2>&1 || true
  fi

  connect_ok=true
  if ! wg-quick up "${TMP_CONFIG}" > "${cycle_dir}/wg_up.log" 2>&1; then
    connect_ok=false
    connect_failures=$((connect_failures + 1))
  fi

  handshake_ok=false
  route_ok=false
  api_health_http=""
  public_ip=""
  ip_changed=false
  iperf_ok=true
  tcpdump_ok=true

  if [[ "${connect_ok}" == "true" ]]; then
    sleep "${CONNECTED_SLEEP}"
    wg show "${INTERFACE_NAME}" > "${cycle_dir}/wg_show.txt" 2>&1 || true
    ip route > "${cycle_dir}/routes_after.txt"
    ip rule show > "${cycle_dir}/rules_after.txt"
    ip route show table 51820 > "${cycle_dir}/routes_table_51820.txt" 2>&1 || true
    if [[ -n "${API_IP}" ]]; then
      ip route get "${API_IP}" > "${cycle_dir}/route_get_after.txt" 2>&1 || true
    fi

    latest_handshake="$(wg show "${INTERFACE_NAME}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2}')"
    if [[ -n "${latest_handshake}" && "${latest_handshake}" != "0" ]]; then
      handshake_ok=true
    else
      handshake_failures=$((handshake_failures + 1))
    fi

    tunnel_route_ok=false
    api_route_ok=true
    if [[ "${SPLIT_TUNNEL}" == "true" ]]; then
      if grep -q "${INTERFACE_NAME}" "${cycle_dir}/routes_table_51820.txt" || grep -q "${INTERFACE_NAME}" "${cycle_dir}/routes_after.txt"; then
        tunnel_route_ok=true
      fi
    else
      if grep -q "default .*${INTERFACE_NAME}" "${cycle_dir}/routes_table_51820.txt"; then
        tunnel_route_ok=true
      fi
    fi
    if [[ -n "${API_IP}" ]]; then
      if grep -q "via ${ORIGINAL_GATEWAY}" "${cycle_dir}/route_get_after.txt" || grep -q "dev ${ORIGINAL_DEV}" "${cycle_dir}/route_get_after.txt"; then
        api_route_ok=true
      else
        api_route_ok=false
      fi
    fi
    if [[ "${tunnel_route_ok}" == "true" && "${api_route_ok}" == "true" ]]; then
      route_ok=true
    fi
    if [[ "${route_ok}" != "true" ]]; then
      route_failures=$((route_failures + 1))
    fi

    api_health_http="$(curl --max-time 10 -sS -o /dev/null -w '%{http_code}' "${HEALTH_URL}" || true)"
    if [[ ! "${api_health_http}" =~ ^2 ]]; then
      api_failures=$((api_failures + 1))
    fi
    public_ip="$(curl --max-time 10 -sS https://api.ipify.org || true)"
    if [[ -n "${BASELINE_IP}" && -n "${public_ip}" && "${BASELINE_IP}" != "${public_ip}" ]]; then
      ip_changed=true
      ip_changed_count=$((ip_changed_count + 1))
    fi

    if [[ -n "${IPERF_HOST}" ]]; then
      if ! iperf3 -c "${IPERF_HOST}" > "${cycle_dir}/iperf3.txt" 2>&1; then
        iperf_ok=false
        iperf_failures=$((iperf_failures + 1))
      fi
    fi

    if [[ "${TCPDUMP_SECONDS}" -gt 0 ]]; then
      if ! timeout "${TCPDUMP_SECONDS}" tcpdump -ni "${INTERFACE_NAME}" > "${cycle_dir}/tcpdump.txt" 2>&1; then
        tcpdump_ok=false
        tcpdump_failures=$((tcpdump_failures + 1))
      fi
    fi

    wg-quick down "${TMP_CONFIG}" > "${cycle_dir}/wg_down.log" 2>&1 || true
  fi

  if [[ -n "${API_IP}" ]]; then
    ip route del "${API_IP}/32" >/dev/null 2>&1 || true
  fi
  ip route > "${cycle_dir}/routes_post_disconnect.txt"
  sleep "${DISCONNECTED_SLEEP}"

  echo "${cycle},${connect_ok},${handshake_ok},${route_ok},${api_health_http},${public_ip},${ip_changed},${iperf_ok},${tcpdump_ok}" >> "${RESULT_CSV}"
done

cat > "${REPORT_MD}" <<EOF
# VPN Stability Report

- Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- API base URL: \`${API_BASE_URL}\`
- API host: \`${API_HOST}\`
- API IP: \`${API_IP}\`
- Rendered config: \`${TMP_CONFIG}\`
- Split tunnel enabled: \`${SPLIT_TUNNEL}\`
- Split tunnel AllowedIPs: \`${SPLIT_TUNNEL_ALLOWED_IPS}\`
- Baseline public IP: \`${BASELINE_IP}\`

## Summary

- Cycles: **${CYCLES}**
- Connect failures: **${connect_failures}**
- Handshake failures: **${handshake_failures}**
- Routing failures: **${route_failures}**
- API reachability failures: **${api_failures}**
- Public IP changed: **${ip_changed_count}/${CYCLES}**
- iperf3 failures: **${iperf_failures}**
- tcpdump failures: **${tcpdump_failures}**

## Diagnostics

- Routing table before first cycle: [routes_before.txt](./cycle_1/routes_before.txt)
- Routing table after first connect: [routes_after.txt](./cycle_1/routes_after.txt)
- Policy routes after first connect: [routes_table_51820.txt](./cycle_1/routes_table_51820.txt)
- API route lookup after first connect: [route_get_after.txt](./cycle_1/route_get_after.txt)
- Handshake proof after first connect: [wg_show.txt](./cycle_1/wg_show.txt)
- Per-cycle CSV: [cycles.csv](./cycles.csv)
EOF

echo "run_dir=${RUN_DIR}"
echo "report=${REPORT_MD}"
