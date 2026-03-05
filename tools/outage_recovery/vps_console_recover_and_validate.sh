#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root on the VPS console." >&2
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

EXPECTED_IP="${SECUREWAVE_EXPECTED_VPS_IP:-}"
CURRENT_IP="$(detect_host_ip)"
if [[ -n "${EXPECTED_IP}" && -n "${CURRENT_IP}" && "${CURRENT_IP}" != "${EXPECTED_IP}" ]]; then
  echo "Refusing to run: current host IP (${CURRENT_IP}) does not match expected VPS IP (${EXPECTED_IP})." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f main.py || ! -f requirements.txt || ! -f run_all_validation_tools.sh ]]; then
  echo "SecureWave repo not found at ${REPO_ROOT}" >&2
  exit 1
fi

mkdir -p /var/log/securewave

echo "==> [1/6] Recovering SSH access"
"${REPO_ROOT}/tools/outage_recovery/emergency_ssh_recovery.sh"

echo "==> [2/6] Restoring OpenVPN/IKEv2 helper scripts"
"${REPO_ROOT}/scripts/ops/restore_openvpn_ikev2_hetzner.sh"

echo "==> [3/6] Preparing backend runtime"
python3 -m venv .venv
. .venv/bin/activate
.venv/bin/pip install --upgrade pip wheel >/dev/null
.venv/bin/pip install -r requirements.txt >/dev/null

echo "==> [4/6] Restarting backend on :8000"
while IFS= read -r backend_pid; do
  [[ -n "${backend_pid}" ]] || continue
  kill "${backend_pid}" >/dev/null 2>&1 || true
done < <(
  ss -tulnp 2>/dev/null | grep -F ':8000 ' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u
)
sleep 1
nohup .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 >/var/log/securewave/backend-live.log 2>&1 &

for _ in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8000/health >/dev/null

echo "==> [5/6] Preparing validation environment"
export API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8000/api}"
export PROFILE_OUTPUT_DIR="${PROFILE_OUTPUT_DIR:-/tmp/securewave_validation_run_$(date +%Y%m%d_%H%M%S)}"
export VALIDATION_EMAIL="${VALIDATION_EMAIL:-}"
export VALIDATION_PASSWORD="${VALIDATION_PASSWORD:-TempPass123!}"

# shellcheck source=tools/validation/_validation_common.sh
source "${REPO_ROOT}/tools/validation/_validation_common.sh"
prepare_validation_environment

echo "==> [6/6] Running validation suite"
"${REPO_ROOT}/run_all_validation_tools.sh"

echo "Validation complete."
echo "Artifacts: ${PROFILE_OUTPUT_DIR}"
echo "Backend log: /var/log/securewave/backend-live.log"
