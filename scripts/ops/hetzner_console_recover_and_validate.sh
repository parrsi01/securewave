#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this as root on the Hetzner VPS console." >&2
  exit 1
fi

detect_host_ip() {
  local detected=""
  detected="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "${detected}" ]]; then
    detected="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  fi
  if [[ -z "${detected}" ]]; then
    detected="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${detected}"
}

EXPECTED_IP="${SECUREWAVE_EXPECTED_VPS_IP:-138.199.204.139}"
CURRENT_IP="$(detect_host_ip)"
if [[ -n "${EXPECTED_IP}" && -n "${CURRENT_IP}" && "${CURRENT_IP}" != "${EXPECTED_IP}" ]]; then
  echo "Refusing to run on this host: current IP (${CURRENT_IP}) != expected (${EXPECTED_IP})." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -x tools/outage_recovery/vps_console_recover_and_validate.sh ]]; then
  chmod +x tools/outage_recovery/vps_console_recover_and_validate.sh
fi

export SECUREWAVE_EXPECTED_VPS_IP="${EXPECTED_IP}"
exec "${REPO_ROOT}/tools/outage_recovery/vps_console_recover_and_validate.sh"
