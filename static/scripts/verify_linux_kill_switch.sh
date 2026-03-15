#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root to inspect iptables OUTPUT rules" >&2
  exit 2
fi

if ! command -v iptables >/dev/null 2>&1; then
  echo "ERROR: iptables not found" >&2
  exit 2
fi
if ! command -v getent >/dev/null 2>&1; then
  echo "ERROR: getent not found" >&2
  exit 2
fi

IFACE="${1:-sw-wg}"
CONFIG_PATH="${2:-$HOME/.config/securewave/sw-wg.conf}"
STATE_DIR="/run/securewave"
POLICY_FILE="${STATE_DIR}/${IFACE}.output-policy"
ENDPOINT_FILE="${STATE_DIR}/${IFACE}.endpoint-ips"

extract_endpoint_host() {
  local config_path="$1"
  awk -F'=' '
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Endpoint[[:space:]]*=/ {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value ~ /^\[/) {
        sub(/^\[/, "", value)
        sub(/\].*$/, "", value)
        print value
        exit
      }
      sub(/:[^:]+$/, "", value)
      print value
      exit
    }
  ' "$config_path"
}

failed=0

policy="$(iptables -S OUTPUT | awk 'NR == 1 {print $3; exit}')"
if [[ "${policy}" != "DROP" ]]; then
  echo "ERROR: OUTPUT policy is '${policy:-<missing>}' (expected DROP)" >&2
  failed=1
fi

if ! iptables -C OUTPUT -o "${IFACE}" -j ACCEPT >/dev/null 2>&1; then
  echo "ERROR: missing OUTPUT allow rule for interface ${IFACE}" >&2
  failed=1
fi

endpoint_ips=()
if [[ -f "${ENDPOINT_FILE}" ]]; then
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] || continue
    endpoint_ips+=("${ip}")
  done < "${ENDPOINT_FILE}"
elif [[ -f "${CONFIG_PATH}" ]]; then
  endpoint_host="$(extract_endpoint_host "${CONFIG_PATH}")"
  if [[ -n "${endpoint_host}" ]]; then
    while IFS= read -r ip; do
      [[ -n "${ip}" ]] || continue
      endpoint_ips+=("${ip}")
    done < <(getent ahostsv4 "${endpoint_host}" | awk '{print $1}' | sort -u)
  fi
fi

if [[ "${#endpoint_ips[@]}" -eq 0 ]]; then
  echo "ERROR: no endpoint IPs found in ${ENDPOINT_FILE} or ${CONFIG_PATH}" >&2
  failed=1
fi

for ip in "${endpoint_ips[@]}"; do
  if ! iptables -C OUTPUT -d "${ip}" -j ACCEPT >/dev/null 2>&1; then
    echo "ERROR: missing OUTPUT allow rule for endpoint ${ip}" >&2
    failed=1
  fi
done

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "WARN: missing saved policy file ${POLICY_FILE}" >&2
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "SecureWave Linux kill-switch verification: FAILED" >&2
  exit 1
fi

echo "SecureWave Linux kill-switch verification: OK"
printf 'iface=%s\n' "${IFACE}"
printf 'output_policy=%s\n' "${policy}"
printf 'endpoint_ips=%s\n' "${endpoint_ips[*]}"
