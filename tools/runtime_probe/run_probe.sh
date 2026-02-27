#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/tunnel_probe.sh"

CONNECT_CMD=""
DISCONNECT_CMD=""
EXPECT_FULL_TUNNEL="${EXPECT_FULL_TUNNEL:-unknown}" # yes|no|unknown

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connect-cmd)
      CONNECT_CMD="${2:-}"
      shift 2
      ;;
    --disconnect-cmd)
      DISCONNECT_CMD="${2:-}"
      shift 2
      ;;
    --expect-full-tunnel)
      EXPECT_FULL_TUNNEL="${2:-unknown}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

args=()
[[ -n "${CONNECT_CMD}" ]] && args+=(--connect-cmd "${CONNECT_CMD}")
[[ -n "${DISCONNECT_CMD}" ]] && args+=(--disconnect-cmd "${DISCONNECT_CMD}")

"${PROBE}" "${args[@]}"

latest_dir="$(ls -1dt "${SCRIPT_DIR}/out"/* 2>/dev/null | head -1 || true)"
if [[ -z "${latest_dir}" ]]; then
  echo "[run_probe] no output directory found" >&2
  exit 1
fi

report="${latest_dir}/REPORT.md"
baseline_route="${latest_dir}/baseline/ip_route.txt"
post_route="${latest_dir}/post_connect/ip_route.txt"
b_ip_file="${latest_dir}/baseline/egress_ipify.txt"
p_ip_file="${latest_dir}/post_connect/egress_ipify.txt"
b_route_get="${latest_dir}/baseline/ip_route_get_1.1.1.1.txt"
p_route_get="${latest_dir}/post_connect/ip_route_get_1.1.1.1.txt"
p_rule_file="${latest_dir}/post_connect/ip_rule_show.txt"
p_dns_lookup_file="${latest_dir}/post_connect/dns_lookup_example.txt"
p_dns_http_file="${latest_dir}/post_connect/dns_https_check.txt"

extract_default() {
  awk '/^\$ /{next} /^default /{print; exit}' "$1" 2>/dev/null || true
}
extract_ip() {
  tr -d '\r' <"$1" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}
extract_iface() {
  awk '/ dev /{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' "$1" 2>/dev/null || true
}
dns_query_success() {
  local lookup_file="$1"
  local http_file="$2"
  if grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}' "$lookup_file" 2>/dev/null; then
    echo "yes"
    return
  fi
  local code
  code="$(grep -Eo 'http_code=[0-9]{3}' "$http_file" 2>/dev/null | head -1 | cut -d= -f2 || true)"
  if [[ "$code" =~ ^[234][0-9][0-9]$ ]]; then
    echo "yes"
    return
  fi
  if grep -Eqi 'NXDOMAIN|SERVFAIL|not known|no address|failed' "$lookup_file" 2>/dev/null; then
    echo "no"
    return
  fi
  if [[ -n "$code" ]]; then
    echo "no"
    return
  fi
  echo "unknown"
}

b_default="$(extract_default "${baseline_route}")"
p_default="$(extract_default "${post_route}")"
b_ip="$(extract_ip "${b_ip_file}")"
p_ip="$(extract_ip "${p_ip_file}")"
b_iface="$(extract_iface "${b_route_get}")"
p_iface="$(extract_iface "${p_route_get}")"

iface_exists_post=0
if grep -Eq 'interface: (wg0|sw-wg|tun0)' "${latest_dir}/post_connect/wg_show.txt" 2>/dev/null || \
   grep -Eq '^[0-9]+: (wg0|sw-wg|tun0):' "${latest_dir}/post_connect/ip_addr.txt" 2>/dev/null; then
  iface_exists_post=1
fi
policy_route_present_post=0
if grep -Eq '51820|fwmark' "${p_rule_file}" 2>/dev/null; then
  policy_route_present_post=1
fi

routing_mode="no_tunnel_routing_detected"
if [[ -n "${b_default}" && -n "${p_default}" && "${b_default}" != "${p_default}" ]]; then
  routing_mode="full_tunnel_default_route"
elif [[ "${policy_route_present_post}" -eq 1 && -n "${b_iface}" && -n "${p_iface}" && "${b_iface}" != "${p_iface}" ]]; then
  routing_mode="policy_tunnel_rule_table"
elif [[ -n "${b_iface}" && -n "${p_iface}" && "${b_iface}" != "${p_iface}" ]]; then
  routing_mode="partial_route_override"
fi

dns_ok="$(dns_query_success "${p_dns_lookup_file}" "${p_dns_http_file}")"

status=0
if [[ "${iface_exists_post}" -eq 1 && -n "${b_ip}" && -n "${p_ip}" && "${b_ip}" == "${p_ip}" ]]; then
  echo "[run_probe][fail] tunnel interface present but egress IP did not change (${b_ip})" >&2
  status=1
fi
if [[ "${iface_exists_post}" -eq 1 && "${dns_ok}" == "no" ]]; then
  echo "[run_probe][fail] tunnel interface present but DNS query validation failed post-connect" >&2
  status=1
fi
if [[ "${iface_exists_post}" -eq 1 && "${dns_ok}" == "unknown" ]]; then
  echo "[run_probe][warn] tunnel interface present but DNS query validation is inconclusive"
fi

if [[ "${EXPECT_FULL_TUNNEL}" == "yes" ]]; then
  if [[ -n "${b_default}" && -n "${p_default}" && "${b_default}" == "${p_default}" ]]; then
    echo "[run_probe][fail] full-tunnel expected but default route did not change" >&2
    status=1
  fi
elif [[ "${EXPECT_FULL_TUNNEL}" == "unknown" ]]; then
  if [[ -n "${b_default}" && -n "${p_default}" && "${b_default}" == "${p_default}" && "${policy_route_present_post}" -ne 1 ]]; then
    echo "[run_probe][warn] default route did not change (full-tunnel expectation unknown)"
  fi
fi

echo "[run_probe] inferred routing mode: ${routing_mode}"
echo "[run_probe] dns validation post-connect: ${dns_ok}"
echo "[run_probe] latest output: ${latest_dir}"
echo "[run_probe] report: ${report}"
exit "${status}"
