#!/usr/bin/env bash
# SecureWave - one-shot remote bootstrap + backend start + validation runner.
#
# Run from your local machine with SSH access to the Hetzner VPS.
#
# Example:
#   VPS_HOST=138.199.204.139 bash scripts/ops/hetzner_full_bootstrap_and_validate.sh
#
# Optional:
#   VPS_USER=root
#   SSH_PORT=22
#   SSH_KEY_PATH=~/.ssh/id_rsa
#   REMOTE_DIR=/opt/securewave
#   API_BASE_URL=http://127.0.0.1:8000/api
#   PROFILE_OUTPUT_DIR=/tmp/securewave_vps_validation
#   VALIDATION_EMAIL=ops@example.com
#   VALIDATION_PASSWORD=TempPass123!
#   ALLOW_NON_HETZNER_HOST=1
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${REPO_ROOT}/tools/validation/_validation_common.sh"
LOCAL_VPS_MODE="${SECUREWAVE_LOCAL_VPS_MODE:-0}"
if [[ "${LOCAL_VPS_MODE}" != "1" ]]; then
  VPS_HOST="${VPS_HOST:?VPS_HOST is required}"
else
  VPS_HOST="${VPS_HOST:-127.0.0.1}"
fi
VPS_USER="${VPS_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/opt/securewave}"
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8000/api}"
PROFILE_OUTPUT_DIR="${PROFILE_OUTPUT_DIR:-/tmp/securewave_vps_validation}"
VALIDATION_EMAIL="${VALIDATION_EMAIL:-}"
VALIDATION_PASSWORD="${VALIDATION_PASSWORD:-TempPass123!}"
ALLOW_NON_HETZNER_HOST="${ALLOW_NON_HETZNER_HOST:-}"

# Local VPS mode is an explicit dev/self-validation path, so default the
# Hetzner host bypass on unless the caller explicitly overrides it.
if [[ "${LOCAL_VPS_MODE}" == "1" && -z "${ALLOW_NON_HETZNER_HOST}" ]]; then
  ALLOW_NON_HETZNER_HOST=1
fi
ALLOW_NON_HETZNER_HOST="${ALLOW_NON_HETZNER_HOST:-0}"

if [[ "${LOCAL_VPS_MODE}" == "1" ]]; then
  REMOTE_DIR="${REPO_ROOT}"
fi

if [[ "${LOCAL_VPS_MODE}" == "1" ]]; then
  echo "==> [1/5] Verifying local repo"
  cd "${REPO_ROOT}"

  if [[ ! -f main.py || ! -f requirements.txt || ! -f tools/provisioning/install_vpn_stack.sh || ! -f run_all_validation_tools.sh ]]; then
    echo "Local repo is missing required SecureWave files: ${REPO_ROOT}" >&2
    exit 1
  fi

  if [[ "${ALLOW_NON_HETZNER_HOST}" == "1" ]]; then
    export SECUREWAVE_ALLOW_NON_HETZNER_HOST=1
  fi

  echo "==> [2/5] Running local provisioning"
  ./tools/provisioning/install_vpn_stack.sh
  if [[ -x ./scripts/ops/restore_openvpn_ikev2_hetzner.sh ]]; then
    echo "      -> Restoring OpenVPN/IKEv2 provisioning helpers"
    ./scripts/ops/restore_openvpn_ikev2_hetzner.sh
  fi

  echo "==> [3/5] Restarting backend on :8000 as root"
  python3 -m venv .venv
  . .venv/bin/activate
  .venv/bin/pip install --upgrade pip wheel >/dev/null
  .venv/bin/pip install -r requirements.txt >/dev/null
  mkdir -p /var/log/securewave

  while IFS= read -r backend_pid; do
    [[ -n "${backend_pid}" ]] || continue
    kill "${backend_pid}" >/dev/null 2>&1 || true
  done < <(ss -tulnp 2>/dev/null | grep -F ':8000 ' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)
  sleep 1
  nohup .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 > /var/log/securewave/backend-live.log 2>&1 &

  for _ in $(seq 1 20); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  curl -fsS http://127.0.0.1:8000/health >/dev/null

  echo "==> [4/5] Preparing validation environment"
  export API_BASE_URL PROFILE_OUTPUT_DIR VALIDATION_EMAIL VALIDATION_PASSWORD
  prepare_validation_environment
  mkdir -p "${PROFILE_OUTPUT_DIR}"

  echo "==> [5/5] Running local validation suite"
  ./run_all_validation_tools.sh
  echo "Validation complete."
  echo "Validation user: ${VALIDATION_EMAIL:-unknown}"
  echo "Artifacts: ${PROFILE_OUTPUT_DIR}"
  exit 0
fi

SSH_CMD=(ssh -o StrictHostKeyChecking=no)
RSYNC_RSH="ssh -o StrictHostKeyChecking=no"
if [[ -n "${SSH_PORT:-}" ]]; then
  SSH_CMD+=(-p "${SSH_PORT}")
  RSYNC_RSH+=" -p ${SSH_PORT}"
fi
if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  SSH_CMD+=(-i "${SSH_KEY_PATH}")
  RSYNC_RSH+=" -i ${SSH_KEY_PATH}"
fi

SSH_TARGET="${VPS_USER}@${VPS_HOST}"

ssh_exec() {
  "${SSH_CMD[@]}" "${SSH_TARGET}" "$@"
}

quote_remote() {
  printf '%q' "$1"
}

echo "==> [1/6] Verifying SSH access"
ssh_exec "echo SSH_OK"

echo "==> [2/6] Preparing remote directory"
ssh_exec "mkdir -p '${REMOTE_DIR}'"

echo "==> [3/6] Syncing full SecureWave repo"
rsync -az --delete \
  --exclude='.git' \
  --exclude='venv/' \
  --exclude='.venv/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.sqlite' \
  --exclude='*.db' \
  --exclude='artifacts/' \
  --exclude='securewave_app/build/' \
  --exclude='securewave_app/.dart_tool/' \
  --exclude='tools/egress_proof/out/' \
  --exclude='tools/external_client_validation/out/' \
  --exclude='tools/runtime_probe/out/' \
  --exclude='tools/token_secret_fix/out/' \
  -e "${RSYNC_RSH}" \
  "${REPO_ROOT}/" "${SSH_TARGET}:${REMOTE_DIR}/"

echo "==> [4/6] Bootstrapping host, backend, and validation user"
ssh_exec "\
REMOTE_DIR=$(quote_remote "${REMOTE_DIR}") \
API_BASE_URL=$(quote_remote "${API_BASE_URL}") \
PROFILE_OUTPUT_DIR=$(quote_remote "${PROFILE_OUTPUT_DIR}") \
VALIDATION_EMAIL=$(quote_remote "${VALIDATION_EMAIL}") \
VALIDATION_PASSWORD=$(quote_remote "${VALIDATION_PASSWORD}") \
ALLOW_NON_HETZNER_HOST=$(quote_remote "${ALLOW_NON_HETZNER_HOST}") \
bash -s" <<'REMOTE_BOOTSTRAP'
set -euo pipefail

: "${REMOTE_DIR:?REMOTE_DIR is required}"
: "${API_BASE_URL:?API_BASE_URL is required}"
: "${PROFILE_OUTPUT_DIR:?PROFILE_OUTPUT_DIR is required}"
: "${VALIDATION_PASSWORD:?VALIDATION_PASSWORD is required}"
: "${ALLOW_NON_HETZNER_HOST:?ALLOW_NON_HETZNER_HOST is required}"

cd "${REMOTE_DIR}"

if [[ ! -f main.py || ! -f requirements.txt || ! -f tools/provisioning/install_vpn_stack.sh || ! -f run_all_validation_tools.sh ]]; then
  echo "Remote directory is missing required SecureWave files: ${REMOTE_DIR}" >&2
  exit 1
fi

if [[ "${ALLOW_NON_HETZNER_HOST}" == "1" ]]; then
  export SECUREWAVE_ALLOW_NON_HETZNER_HOST=1
fi

echo "  -> Running provisioning"
./tools/provisioning/install_vpn_stack.sh
if [[ -x ./scripts/ops/restore_openvpn_ikev2_hetzner.sh ]]; then
  echo "  -> Restoring OpenVPN/IKEv2 provisioning helpers"
  ./scripts/ops/restore_openvpn_ikev2_hetzner.sh
fi

echo "  -> Preparing backend venv"
python3 -m venv .venv
. .venv/bin/activate
.venv/bin/pip install --upgrade pip wheel >/dev/null
.venv/bin/pip install -r requirements.txt >/dev/null

mkdir -p /var/log/securewave

echo "  -> Restarting backend on :8000"
while IFS= read -r backend_pid; do
  [[ -n "${backend_pid}" ]] || continue
  kill "${backend_pid}" >/dev/null 2>&1 || true
done < <(ss -tulnp 2>/dev/null | grep -F ':8000 ' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)
sleep 1
nohup .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 > /var/log/securewave/backend-live.log 2>&1 &

for _ in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS http://127.0.0.1:8000/health >/dev/null

echo "  -> Preparing validation environment"
# shellcheck source=tools/validation/_validation_common.sh
source "${REMOTE_DIR}/tools/validation/_validation_common.sh"
export API_BASE_URL PROFILE_OUTPUT_DIR VALIDATION_EMAIL VALIDATION_PASSWORD
prepare_validation_environment

printf '%s\n' "${AUTH_TOKEN}" > /tmp/securewave_validation_token
printf '%s\n' "${AUTH_TOKEN_WIREGUARD:-${AUTH_TOKEN}}" > /tmp/securewave_validation_wireguard_token
printf '%s\n' "${AUTH_TOKEN_OPENVPN:-${AUTH_TOKEN}}" > /tmp/securewave_validation_openvpn_token
printf '%s\n' "${AUTH_TOKEN_IKEV2:-${AUTH_TOKEN}}" > /tmp/securewave_validation_ikev2_token
printf '%s\n' "${VALIDATION_EMAIL:-}" > /tmp/securewave_validation_email
printf '%s\n' "${VALIDATION_PASSWORD}" > /tmp/securewave_validation_password
printf '%s\n' "${PROFILE_OUTPUT_DIR}" > /tmp/securewave_validation_profile_dir
REMOTE_BOOTSTRAP

echo "==> [5/6] Running remote validation suite"
ssh_exec "\
REMOTE_DIR=$(quote_remote "${REMOTE_DIR}") \
API_BASE_URL=$(quote_remote "${API_BASE_URL}") \
PROFILE_OUTPUT_DIR=$(quote_remote "${PROFILE_OUTPUT_DIR}") \
ALLOW_NON_HETZNER_HOST=$(quote_remote "${ALLOW_NON_HETZNER_HOST}") \
bash -s" <<'REMOTE_VALIDATE'
set -euo pipefail

: "${REMOTE_DIR:?REMOTE_DIR is required}"
: "${API_BASE_URL:?API_BASE_URL is required}"
: "${PROFILE_OUTPUT_DIR:?PROFILE_OUTPUT_DIR is required}"
: "${ALLOW_NON_HETZNER_HOST:?ALLOW_NON_HETZNER_HOST is required}"

cd "${REMOTE_DIR}"
if [[ "${ALLOW_NON_HETZNER_HOST}" == "1" ]]; then
  export SECUREWAVE_ALLOW_NON_HETZNER_HOST=1
fi

export API_BASE_URL
export PROFILE_OUTPUT_DIR
export AUTH_TOKEN="$(cat /tmp/securewave_validation_wireguard_token)"
export AUTH_TOKEN_WIREGUARD="${AUTH_TOKEN}"
export AUTH_TOKEN_OPENVPN="$(cat /tmp/securewave_validation_openvpn_token)"
export AUTH_TOKEN_IKEV2="$(cat /tmp/securewave_validation_ikev2_token)"

./run_all_validation_tools.sh
REMOTE_VALIDATE

echo "==> [6/6] Validation complete"
echo "Remote repo: ${SSH_TARGET}:${REMOTE_DIR}"
echo "API_BASE_URL: ${API_BASE_URL}"
echo "Validation user: $(ssh_exec "cat /tmp/securewave_validation_email")"
echo "Validation password: $(ssh_exec "cat /tmp/securewave_validation_password")"
echo "Artifacts: $(ssh_exec "cat /tmp/securewave_validation_profile_dir")"
echo "Backend log: ssh ${SSH_TARGET} 'tail -100 /var/log/securewave/backend-live.log'"
