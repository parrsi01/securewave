#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

LOG_FILE="/tmp/securewave_full_validation.log"

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

if [[ ! -f "scripts/ops/hetzner_full_bootstrap_and_validate.sh" ]]; then
  echo "Missing wrapper script: scripts/ops/hetzner_full_bootstrap_and_validate.sh" >&2
  exit 1
fi

if [[ ! -f "tools/validation/validate_vpn_wireguard.sh" ]]; then
  echo "Missing validation script: tools/validation/validate_vpn_wireguard.sh" >&2
  exit 1
fi

if [[ ! -f "tools/validation/validate_vpn_openvpn.sh" ]]; then
  echo "Missing validation script: tools/validation/validate_vpn_openvpn.sh" >&2
  exit 1
fi

if [[ ! -f "tools/validation/validate_vpn_ikev2.sh" ]]; then
  echo "Missing validation script: tools/validation/validate_vpn_ikev2.sh" >&2
  exit 1
fi

chmod +x \
  scripts/ops/hetzner_full_bootstrap_and_validate.sh \
  tools/validation/validate_vpn_wireguard.sh \
  tools/validation/validate_vpn_openvpn.sh \
  tools/validation/validate_vpn_ikev2.sh

export API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8000/api}"
export PROFILE_OUTPUT_DIR="${PROFILE_OUTPUT_DIR:-/tmp/securewave_validation_run_$(date +%Y%m%d_%H%M%S)}"
export SECUREWAVE_LOCAL_VPS_MODE=1
export ALLOW_NON_HETZNER_HOST="${ALLOW_NON_HETZNER_HOST:-1}"
export AUTH_TOKEN="${AUTH_TOKEN:-}"
mkdir -p "${PROFILE_OUTPUT_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[START] SecureWave full VPS validation"
echo "API_BASE_URL=${API_BASE_URL}"
echo "PROFILE_OUTPUT_DIR=${PROFILE_OUTPUT_DIR}"
echo "LOG_FILE=${LOG_FILE}"

scripts/ops/hetzner_full_bootstrap_and_validate.sh
