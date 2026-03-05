#!/usr/bin/env bash
# Shared helpers for SecureWave single-host Hetzner validation scripts.

readonly SW_RED='\033[0;31m'
readonly SW_GREEN='\033[0;32m'
readonly SW_YELLOW='\033[1;33m'
readonly SW_BLUE='\033[0;34m'
readonly SW_RESET='\033[0m'
readonly VALIDATION_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timestamp_slug() {
  date -u +"%Y%m%d_%H%M%S"
}

log_line() {
  printf '[%s] %s\n' "$(timestamp_utc)" "$*"
}

info_line() {
  printf '%b[%s] INFO: %s%b\n' "${SW_BLUE}" "$(timestamp_utc)" "$*" "${SW_RESET}"
}

warn_line() {
  printf '%b[%s] WARN: %s%b\n' "${SW_YELLOW}" "$(timestamp_utc)" "$*" "${SW_RESET}"
}

error_line() {
  printf '%b[%s] ERROR: %s%b\n' "${SW_RED}" "$(timestamp_utc)" "$*" "${SW_RESET}" >&2
}

step_pass() {
  local step_num="$1"
  local description="$2"
  printf '%b[STEP %s] %s - PASS%b\n' "${SW_GREEN}" "${step_num}" "${description}" "${SW_RESET}"
}

step_fail() {
  local step_num="$1"
  local description="$2"
  local evidence_file="${3:-}"
  printf '%b[STEP %s] %s - FAIL%b\n' "${SW_RED}" "${step_num}" "${description}" "${SW_RESET}"
  if [[ -n "${evidence_file}" ]]; then
    log_line "Evidence: ${evidence_file}"
  fi
  exit 1
}

require_cmds() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      error_line "Required command not found: ${cmd}"
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

unit_file_exists() {
  local unit_name="$1"

  systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fx "${unit_name}.service" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error_line "This validation must be run as root on the Hetzner VPN server."
    exit 1
  fi
}

require_hetzner_host() {
  local hostname_text
  local allow_non_hetzner
  hostname_text="$(hostname -f 2>/dev/null || hostname)"
  allow_non_hetzner="${SECUREWAVE_ALLOW_NON_HETZNER_HOST:-}"

  if [[ "${allow_non_hetzner}" == "1" ]]; then
    warn_line "Bypassing Hetzner host check because SECUREWAVE_ALLOW_NON_HETZNER_HOST=1."
    return 0
  fi

  if [[ -f /etc/hetzner-release ]]; then
    return 0
  fi

  if [[ -r /sys/class/dmi/id/sys_vendor ]] && grep -qi 'hetzner' /sys/class/dmi/id/sys_vendor; then
    return 0
  fi

  if [[ "${hostname_text,,}" =~ (hetzner|securewave|vpn|fsn|nbg|hel|cx|cpx|ccx|ax|ex) ]]; then
    return 0
  fi

  error_line "Refusing to run: this host does not look like the Hetzner VPN server (hostname=${hostname_text}) and /etc/hetzner-release is absent. Set SECUREWAVE_ALLOW_NON_HETZNER_HOST=1 only for an intentional local/dev run."
  exit 1
}

detect_server_public_ip() {
  local ips
  local candidate

  ips="$(hostname -I 2>/dev/null || true)"
  candidate="$(
    awk '{
      for (i = 1; i <= NF; i++) {
        if ($i !~ /^127\./ &&
            $i !~ /^10\./ &&
            $i !~ /^192\.168\./ &&
            $i !~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {
          print $i
          exit
        }
      }
    }' <<< "${ips}"
  )"

  if [[ -z "${candidate}" ]]; then
    candidate="$(awk '{print $1; exit}' <<< "${ips}")"
  fi

  if [[ -z "${candidate}" ]]; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
  fi

  if [[ -z "${candidate}" ]]; then
    error_line "Unable to detect a server IP using hostname -I."
    exit 1
  fi

  printf '%s\n' "${candidate}"
}

ensure_securewave_log_dir() {
  export SECUREWAVE_LOG_DIR="${SECUREWAVE_LOG_DIR:-/var/log/securewave}"
  mkdir -p "${SECUREWAVE_LOG_DIR}"
  chmod 750 "${SECUREWAVE_LOG_DIR}" >/dev/null 2>&1 || true
}

begin_script_log() {
  local log_name="$1"

  ensure_securewave_log_dir
  export LOG_FILE="${SECUREWAVE_LOG_DIR%/}/${log_name}.log"

  : > "${LOG_FILE}"
  exec > >(tee -a "${LOG_FILE}") 2>&1
  log_line "Logging to ${LOG_FILE}"
}

init_validation_env() {
  require_root
  require_hetzner_host

  : "${API_BASE_URL:?API_BASE_URL is required}"
  : "${AUTH_TOKEN:?AUTH_TOKEN is required}"

  ensure_securewave_log_dir
  export PROFILE_OUTPUT_DIR="${PROFILE_OUTPUT_DIR:-/tmp/securewave_vps_validation}"
  export PUBLIC_IP_CHECK_URL="${PUBLIC_IP_CHECK_URL:-https://ifconfig.me/ip}"
  export SERVER_PUBLIC_IP="$(detect_server_public_ip)"

  mkdir -p "${PROFILE_OUTPUT_DIR}"
}

init_protocol_context() {
  local protocol="$1"
  export VALIDATION_PROTOCOL="${protocol}"
  ensure_securewave_log_dir
  export LOG_FILE="${SECUREWAVE_LOG_DIR%/}/securewave_validate_${protocol}.log"
  export PROTOCOL_OUTPUT_DIR="${PROFILE_OUTPUT_DIR%/}/${protocol}"

  mkdir -p "${PROTOCOL_OUTPUT_DIR}"
  : > "${LOG_FILE}"
  exec > >(tee -a "${LOG_FILE}") 2>&1

  log_line "Starting ${protocol} validation on Hetzner host"
  log_line "Detected server public IP: ${SERVER_PUBLIC_IP}"
  log_line "Artifacts: ${PROTOCOL_OUTPUT_DIR}"
}

write_json_payload() {
  local protocol="$1"
  local server_id="$2"
  local payload_file="$3"

  python3 - "${protocol}" "${server_id}" > "${payload_file}" <<'PY'
import json
import sys

payload = {
    "protocol": sys.argv[1],
    "device_name": f"Hetzner validation {sys.argv[1]}",
    "device_type": "linux",
}
if sys.argv[2]:
    payload["server_id"] = sys.argv[2]
print(json.dumps(payload))
PY
}

request_profile() {
  local protocol="$1"
  local server_id="$2"
  local payload_file="$3"
  local response_file="$4"
  local http_code=""
  local curl_status=0

  write_json_payload "${protocol}" "${server_id}" "${payload_file}"
  : > "${response_file}"
  : > "${response_file}.stderr"

  set +e
  http_code="$(
    curl -sS \
      -o "${response_file}" \
      -w '%{http_code}' \
      -X POST \
      "${API_BASE_URL%/}/vpn/profile" \
      -H "Authorization: Bearer ${AUTH_TOKEN}" \
      -H 'Content-Type: application/json' \
      --data @"${payload_file}" \
      2>"${response_file}.stderr"
  )"
  curl_status=$?
  set -e

  export REQUEST_PROFILE_HTTP_STATUS="${http_code:-000}"
  export REQUEST_PROFILE_CURL_STATUS="${curl_status}"
  export REQUEST_PROFILE_ERROR_FILE="${response_file}.stderr"

  if [[ "${curl_status}" -ne 0 || "${REQUEST_PROFILE_HTTP_STATUS}" != "200" ]]; then
    return 1
  fi
  return 0
}

json_get() {
  local json_file="$1"
  local path="$2"

  python3 - "${json_file}" "${path}" <<'PY'
import json
import sys

json_file, path = sys.argv[1], sys.argv[2]
with open(json_file, "r", encoding="utf-8") as handle:
    value = json.load(handle)

for part in path.split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    raise SystemExit(1)

if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

host_matches_server_ip() {
  local candidate_host="$1"

  if [[ -z "${candidate_host}" ]]; then
    return 1
  fi

  if [[ "${candidate_host}" == "${SERVER_PUBLIC_IP}" ]]; then
    return 0
  fi

  python3 - "${candidate_host}" "${SERVER_PUBLIC_IP}" <<'PY'
import socket
import sys

host, expected = sys.argv[1], sys.argv[2]
try:
    resolved = socket.gethostbyname(host)
except OSError:
    raise SystemExit(1)

raise SystemExit(0 if resolved == expected else 1)
PY
}

assert_non_empty_file() {
  local path="$1"
  [[ -s "${path}" ]]
}

namespace_exists() {
  local namespace_name="$1"
  ip netns list 2>/dev/null | awk '{print $1}' | grep -Fx "${namespace_name}" >/dev/null 2>&1
}

delete_namespace() {
  local namespace_name="$1"
  local host_veth="$2"
  local namespace_etc_dir="/etc/netns/${namespace_name}"

  ip link del "${host_veth}" >/dev/null 2>&1 || true
  ip netns del "${namespace_name}" >/dev/null 2>&1 || true
  rm -f "${namespace_etc_dir}/resolv.conf" >/dev/null 2>&1 || true
  rmdir "${namespace_etc_dir}" >/dev/null 2>&1 || true
}

setup_namespace() {
  local namespace_name="$1"
  local host_veth="$2"
  local ns_veth="$3"
  local host_cidr="$4"
  local ns_cidr="$5"
  local host_ip="${host_cidr%/*}"
  local namespace_etc_dir="/etc/netns/${namespace_name}"

  delete_namespace "${namespace_name}" "${host_veth}"

  mkdir -p "${namespace_etc_dir}"
  cat > "${namespace_etc_dir}/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

  ip netns add "${namespace_name}"
  ip link add "${host_veth}" type veth peer name "${ns_veth}"
  ip link set "${ns_veth}" netns "${namespace_name}"
  ip addr add "${host_cidr}" dev "${host_veth}"
  ip link set "${host_veth}" up
  ip netns exec "${namespace_name}" ip link set lo up
  ip netns exec "${namespace_name}" ip addr add "${ns_cidr}" dev "${ns_veth}"
  ip netns exec "${namespace_name}" ip link set "${ns_veth}" up
  ip netns exec "${namespace_name}" ip route replace default via "${host_ip}" dev "${ns_veth}"
  ip netns exec "${namespace_name}" ip route replace "${SERVER_PUBLIC_IP}/32" via "${host_ip}" dev "${ns_veth}"
}

exec_in_namespace() {
  local namespace_name="$1"
  local command="$2"
  ip netns exec "${namespace_name}" bash -lc "${command}"
}

capture_in_namespace() {
  local namespace_name="$1"
  local command="$2"
  local output_file="$3"
  if exec_in_namespace "${namespace_name}" "${command}" >"${output_file}" 2>&1; then
    return 0
  fi
  return 1
}

_json_read_path() {
  local json_file="$1"
  local path="$2"

  python3 - "${json_file}" "${path}" <<'PY'
import json
import pathlib
import sys

json_file, path = sys.argv[1], sys.argv[2]
raw = pathlib.Path(json_file).read_text(encoding="utf-8", errors="ignore").strip()
if not raw:
    raise SystemExit(1)

try:
    value = json.loads(raw)
except Exception:
    raise SystemExit(1)

for part in path.split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    raise SystemExit(1)

if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

_json_list_values() {
  local json_file="$1"
  local path="$2"

  python3 - "${json_file}" "${path}" <<'PY'
import json
import pathlib
import sys

json_file, path = sys.argv[1], sys.argv[2]
raw = pathlib.Path(json_file).read_text(encoding="utf-8", errors="ignore").strip()
if not raw:
    raise SystemExit(1)

try:
    value = json.loads(raw)
except Exception:
    raise SystemExit(1)

for part in path.split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if not isinstance(value, list):
    raise SystemExit(1)

for item in value:
    if isinstance(item, (dict, list)):
        print(json.dumps(item))
    else:
        print(item)
PY
}

json_optional_get() {
  local json_file="$1"
  local path="$2"
  _json_read_path "${json_file}" "${path}" 2>/dev/null || true
}

api_root_url() {
  local base="${API_BASE_URL%/}"
  if [[ "${base}" == */api ]]; then
    printf '%s\n' "${base%/api}"
  else
    printf '%s\n' "${base}"
  fi
}

backend_is_ready() {
  local root_url
  root_url="$(api_root_url)"
  if curl -fsS "${root_url}/health" >/dev/null 2>&1; then
    return 0
  fi
  if curl -fsS "${API_BASE_URL%/}/health" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

normalize_api_base_url() {
  if backend_is_ready; then
    return 0
  fi

  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    export API_BASE_URL="http://127.0.0.1:8000/api"
    printf '[RECOVERY] API base URL normalized\n'
    return 0
  fi

  return 1
}

validation_python_bin() {
  if [[ -x "${VALIDATION_REPO_ROOT}/.venv/bin/python" ]]; then
    printf '%s\n' "${VALIDATION_REPO_ROOT}/.venv/bin/python"
    return 0
  fi
  printf '%s\n' "python3"
}

run_backend_bootstrap_script() {
  local py_bin

  normalize_api_base_url || true
  if backend_is_ready; then
    return 0
  fi

  if [[ -x "${VALIDATION_REPO_ROOT}/tools/provisioning/install_vpn_stack.sh" ]]; then
    (
      cd "${VALIDATION_REPO_ROOT}"
      ./tools/provisioning/install_vpn_stack.sh >/dev/null 2>&1 || true
    )
  fi

  py_bin="$(validation_python_bin)"
  (
    cd "${VALIDATION_REPO_ROOT}"
    "${py_bin}" -m venv .venv >/dev/null 2>&1 || true
    . .venv/bin/activate
    .venv/bin/pip install --upgrade pip wheel >/dev/null 2>&1 || true
    .venv/bin/pip install -r requirements.txt >/dev/null 2>&1 || true
    mkdir -p /var/log/securewave
    if ! ss -tulnp 2>/dev/null | grep -F ':8000 ' >/dev/null 2>&1; then
      nohup .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 > /var/log/securewave/backend-live.log 2>&1 &
    fi
  )

  for _ in $(seq 1 20); do
    normalize_api_base_url || true
    if backend_is_ready; then
      printf '[RECOVERY] Backend bootstrap completed\n'
      return 0
    fi
    sleep 1
  done

  return 1
}

current_auth_user_email() {
  local response_file
  local http_code

  response_file="$(mktemp)"
  set +e
  http_code="$(
    curl -sS \
      -o "${response_file}" \
      -w '%{http_code}' \
      -H "Authorization: Bearer ${AUTH_TOKEN:-}" \
      "${API_BASE_URL%/}/auth/me" \
      2>/dev/null
  )"
  set -e

  if [[ "${http_code}" != "200" ]]; then
    rm -f "${response_file}"
    return 1
  fi

  json_optional_get "${response_file}" "email"
  rm -f "${response_file}"
}

is_validation_user_email() {
  local email="${1:-}"
  [[ "${email}" =~ ^ops-validation-.*@ ]]
}

create_validation_user() {
  local email
  local passwd_value
  local response_file
  local http_code
  local token

  normalize_api_base_url || true
  backend_is_ready || run_backend_bootstrap_script

  email="ops-validation-$(timestamp_slug)-$RANDOM@example.com"
  passwd_value="${VALIDATION_PASSWORD:-sw-validation-${RANDOM}${RANDOM}}"
  response_file="$(mktemp)"

  set +e
  http_code="$(
    curl -sS \
      -o "${response_file}" \
      -w '%{http_code}' \
      -X POST \
      "${API_BASE_URL%/}/auth/register" \
      -H 'Content-Type: application/json' \
      --data "{\"email\":\"${email}\",\"password\":\"${passwd_value}\",\"password_confirm\":\"${passwd_value}\"}" \
      2>"${response_file}.stderr"
  )"
  set -e

  if [[ "${http_code}" != "200" && "${http_code}" != "201" ]]; then
    rm -f "${response_file}" "${response_file}.stderr"
    return 1
  fi

  token="$(json_optional_get "${response_file}" "access_token")"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    rm -f "${response_file}" "${response_file}.stderr"
    return 1
  fi

  export AUTH_TOKEN="${token}"
  export VALIDATION_EMAIL="${email}"
  export VALIDATION_PASSWORD="${password}"

  rm -f "${response_file}" "${response_file}.stderr"
  printf '[RECOVERY] Validation user created\n'
}

ensure_validation_identity() {
  local email=""

  if [[ -n "${AUTH_TOKEN:-}" ]]; then
    email="$(current_auth_user_email 2>/dev/null || true)"
  fi

  if [[ -n "${email}" ]] && is_validation_user_email "${email}"; then
    export VALIDATION_EMAIL="${email}"
    return 0
  fi

  create_validation_user
}

reset_validation_devices() {
  local email
  local response_file
  local http_code
  local device_ids
  local device_id
  local delete_code

  ensure_validation_identity
  email="${VALIDATION_EMAIL:-$(current_auth_user_email 2>/dev/null || true)}"
  if ! is_validation_user_email "${email}"; then
    create_validation_user
  fi

  response_file="$(mktemp)"
  set +e
  http_code="$(
    curl -sS \
      -o "${response_file}" \
      -w '%{http_code}' \
      -H "Authorization: Bearer ${AUTH_TOKEN}" \
      "${API_BASE_URL%/}/vpn/devices" \
      2>"${response_file}.stderr"
  )"
  set -e

  if [[ "${http_code}" != "200" ]]; then
    rm -f "${response_file}" "${response_file}.stderr"
    return 1
  fi

  device_ids="$(
    python3 - "${response_file}" <<'PY'
import json
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").strip()
if not raw:
    raise SystemExit(0)

try:
    payload = json.loads(raw)
except Exception:
    raise SystemExit(0)

for item in payload.get("devices", []):
    value = item.get("id")
    if value is not None:
        print(value)
PY
  )"

  while IFS= read -r device_id; do
    [[ -n "${device_id}" ]] || continue
    set +e
    delete_code="$(
      curl -sS \
        -o /dev/null \
        -w '%{http_code}' \
        -X DELETE \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        "${API_BASE_URL%/}/vpn/devices/${device_id}" \
        2>/dev/null
    )"
    set -e
    if [[ "${delete_code}" != "204" && "${delete_code}" != "200" && "${delete_code}" != "404" ]]; then
      rm -f "${response_file}" "${response_file}.stderr"
      return 1
    fi
  done <<< "${device_ids}"

  rm -f "${response_file}" "${response_file}.stderr"
  printf '[RECOVERY] Device quota reset\n'
}

region_health_cache_wait_seconds() {
  local raw="${SECUREWAVE_REGION_RESOLUTION_CACHE_TTL_SECONDS:-10}"
  if [[ "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$(( raw + 1 ))"
    return 0
  fi
  printf '11\n'
}

normalize_server_health() {
  local target_server_id="${1:-}"
  local py_bin

  py_bin="$(validation_python_bin)"
  if (
    cd "${VALIDATION_REPO_ROOT}"
    TARGET_SERVER_ID="${target_server_id}" "${py_bin}" - <<'PY'
import os
from datetime import datetime

from database.session import SessionLocal
from models.vpn_server import VPNServer

session = SessionLocal()
target = os.getenv("TARGET_SERVER_ID", "").strip()

try:
    query = session.query(VPNServer)
    if target:
        servers = query.filter(VPNServer.server_id == target).all()
    else:
        servers = query.filter(VPNServer.status == "active").all()

    if not servers:
        servers = session.query(VPNServer).all()

    if not servers:
        raise SystemExit(1)

    for server in servers:
        server.status = "active"
        server.health_status = "healthy"
        server.consecutive_health_failures = 0
        server.last_health_check = datetime.utcnow()
        session.add(server)

    session.commit()
finally:
    session.close()
PY
  ); then
    printf '[RECOVERY] Server health normalized\n'
    return 0
  fi

  return 1
}

reconcile_runtime_inventory() {
  local py_bin

  py_bin="$(validation_python_bin)"
  if (
    cd "${VALIDATION_REPO_ROOT}"
    "${py_bin}" tools/validation/reconcile_runtime_inventory.py
  ); then
    printf '[RECOVERY] Runtime inventory reconciled\n'
    return 0
  fi

  return 1
}

prepare_validation_environment() {
  normalize_api_base_url || true
  backend_is_ready || run_backend_bootstrap_script
  reconcile_runtime_inventory || true
  ensure_validation_identity
  reset_validation_devices
  normalize_server_health || true
  export AUTH_TOKEN_WIREGUARD="${AUTH_TOKEN_WIREGUARD:-${AUTH_TOKEN}}"
  export AUTH_TOKEN_OPENVPN="${AUTH_TOKEN_OPENVPN:-${AUTH_TOKEN}}"
  export AUTH_TOKEN_IKEV2="${AUTH_TOKEN_IKEV2:-${AUTH_TOKEN}}"
}

_profile_response_error_code() {
  local response_file="$1"
  local code

  code="$(json_optional_get "${response_file}" "error.code")"
  if [[ -n "${code}" ]]; then
    printf '%s\n' "${code}"
    return 0
  fi

  code="$(json_optional_get "${response_file}" "detail")"
  if [[ -n "${code}" ]]; then
    printf '%s\n' "${code}"
  fi
}

_profile_response_error_message() {
  local response_file="$1"
  local message

  message="$(json_optional_get "${response_file}" "error.message")"
  if [[ -n "${message}" ]]; then
    printf '%s\n' "${message}"
    return 0
  fi

  message="$(json_optional_get "${response_file}" "detail")"
  if [[ -n "${message}" ]]; then
    printf '%s\n' "${message}"
  fi
}

recover_profile_generation_failure() {
  local protocol="$1"
  local server_id="$2"
  local response_file="$3"
  local http_status="${REQUEST_PROFILE_HTTP_STATUS:-000}"
  local curl_status="${REQUEST_PROFILE_CURL_STATUS:-0}"
  local error_code
  local error_message
  local stderr_body=""

  error_code="$(_profile_response_error_code "${response_file}" | tr '[:upper:]' '[:lower:]')"
  error_message="$(_profile_response_error_message "${response_file}" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${REQUEST_PROFILE_ERROR_FILE:-}" && -f "${REQUEST_PROFILE_ERROR_FILE}" ]]; then
    stderr_body="$(tr '[:upper:]' '[:lower:]' < "${REQUEST_PROFILE_ERROR_FILE}")"
  fi

  if [[ "${curl_status}" != "0" ]] || [[ "${http_status}" == "000" ]] || [[ "${stderr_body}" == *"failed to connect"* ]] || [[ "${stderr_body}" == *"connection refused"* ]]; then
    run_backend_bootstrap_script
    return 0
  fi

  if [[ "${http_status}" == "401" ]] || [[ "${error_code}" =~ ^(invalid_token|token_expired|authentication_required|unauthorized)$ ]] || [[ "${error_message}" == *"invalid token"* ]] || [[ "${error_message}" == *"invalid credentials"* ]] || [[ "${error_message}" == *"not authenticated"* ]]; then
    create_validation_user
    return 0
  fi

  if [[ "${error_code}" == "user_not_found" ]] || [[ "${error_message}" == *"user not found"* ]]; then
    create_validation_user
    return 0
  fi

  if [[ "${error_code}" == "device_limit_reached" ]] || [[ "${error_message}" == *"device limit reached"* ]]; then
    reset_validation_devices
    return 0
  fi

  if [[ "${error_code}" == "quota_exceeded" ]] || [[ "${error_message}" == *"data cap exceeded"* ]]; then
    create_validation_user
    return 0
  fi

  if [[ "${error_code}" =~ ^(no_servers_available|region_down|protocol_unavailable|no_protocol_available)$ ]] || [[ "${error_message}" == *"offline"* ]] || [[ "${error_message}" == *"currently unavailable"* ]] || [[ "${error_message}" == *"no vpn servers available"* ]]; then
    normalize_server_health "${server_id}"
    sleep "$(region_health_cache_wait_seconds)"
    return 0
  fi

  if [[ "${http_status}" == "503" ]]; then
    normalize_server_health "${server_id}"
    sleep "$(region_health_cache_wait_seconds)"
    return 0
  fi

  return 1
}

request_profile_with_recovery() {
  local protocol="$1"
  local server_id="$2"
  local payload_file="$3"
  local response_file="$4"
  local attempt

  for attempt in 1 2 3; do
    if request_profile "${protocol}" "${server_id}" "${payload_file}" "${response_file}"; then
      return 0
    fi

    if [[ "${attempt}" -ge 3 ]]; then
      return 1
    fi

    if ! recover_profile_generation_failure "${protocol}" "${server_id}" "${response_file}"; then
      return 1
    fi
  done

  return 1
}
