#!/usr/bin/env bash
set -euo pipefail

# Blue/green canary deploy for a single-host Hetzner setup:
# - Start a new backend on a canary port from a detached `git worktree`.
# - Validate health + /metrics (and optional alert gating).
# - Optionally promote by switching the Nginx upstream port.
# - Roll back (switch upstream back) on threshold breach.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REF="HEAD"
CANARY_HOST="${CANARY_HOST:-127.0.0.1}"
CANARY_PORT="${CANARY_PORT:-8081}"
CANARY_WORKERS="${CANARY_WORKERS:-1}"
CANARY_TIMEOUT_SECONDS="${CANARY_TIMEOUT_SECONDS:-90}"
STABILIZE_SECONDS="${STABILIZE_SECONDS:-20}"
PROMOTE="false"
STOP_AFTER_CHECKS="false"
RUN_ID=""
WORKTREE_ROOT="${CANARY_WORKTREE_ROOT:-$ROOT_DIR/.canary/worktrees}"
NGINX_CONF="${NGINX_SITE_CONF:-/etc/nginx/sites-available/securewave_preview.conf}"

FAIL_REASON=""
STATUS="unknown" # pass|fail

OUT_DIR=""
WORKTREE_DIR=""
PID_FILE=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --ref <git-ref>            Git ref/sha to deploy (default: HEAD)
  --canary-host <host>       Bind host for canary (default: 127.0.0.1)
  --canary-port <port>       Bind port for canary (default: 8081)
  --promote                  Switch Nginx upstream to canary port (requires root)
  --nginx-conf <path>        Nginx site conf to edit (default: /etc/nginx/sites-available/securewave_preview.conf)
  --stabilize-seconds <n>    Post-promotion stabilize window (default: 20)
  --stop-after-checks        Stop canary after validation when not promoting
  --run-id <id>              Override run id (default: <utc_ts>_<shortsha>)

Environment:
  CANARY_WORKERS             Gunicorn workers for canary (default: 1)
  CANARY_TIMEOUT_SECONDS     Health check timeout (default: 90)
  CANARY_WORKTREE_ROOT       Where git worktrees are created (default: .canary/worktrees)
  ALERT_API_TOKEN / ALERT_API_EMAIL+ALERT_API_PASSWORD (optional)

Outputs:
  - artifacts/canary/<run_id>/
  - artifacts/canary_report.md (latest)
EOF
}

die() {
  local msg="$1"
  FAIL_REASON="$msg"
  STATUS="fail"
  finalize || true
  cleanup || true
  echo "ERROR: ${msg}" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

port_in_use() {
  local host="$1"
  local port="$2"
  if command -v ss >/dev/null 2>&1; then
    set +e
    ss -ltn "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $0}' | grep -q .
    local rc=$?
    set -e
    [[ $rc -eq 0 ]] && return 0
    return 1
  fi
  # Fallback: try connecting. (This may hang on firewalled configs; keep it short.)
  if command -v bash >/dev/null 2>&1; then
    timeout 1 bash -c "echo >/dev/tcp/${host}/${port}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

stop_pid() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 0
  fi
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi
  kill "$pid" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    if kill -0 "$pid" >/dev/null 2>&1; then
      sleep 0.25
    else
      return 0
    fi
  done
  kill -9 "$pid" >/dev/null 2>&1 || true
  return 0
}

stop_canary() {
  if [[ -n "${PID_FILE:-}" && -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    stop_pid "$pid"
    rm -f "${PID_FILE}" >/dev/null 2>&1 || true
  fi
}

cleanup_worktree() {
  if [[ -n "${WORKTREE_DIR:-}" && -d "${WORKTREE_DIR}" ]]; then
    git -C "${ROOT_DIR}" worktree remove --force "${WORKTREE_DIR}" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  # Only stop the canary automatically when:
  # - the run failed, or
  # - operator requested --stop-after-checks and we didn't promote.
  if [[ "${STATUS}" != "pass" || ( "${STOP_AFTER_CHECKS}" == "true" && "${PROMOTE}" != "true" ) ]]; then
    stop_canary || true
  fi
  if [[ "${STATUS}" != "pass" ]]; then
    cleanup_worktree || true
  fi
}

http_code() {
  local url="$1"
  curl -sS -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null || echo "000"
}

wait_http_200() {
  local url="$1"
  local timeout_s="$2"
  local deadline
  deadline="$(($(date +%s) + timeout_s))"
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if [[ "$(http_code "$url")" == "200" ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

extract_nginx_upstream_port() {
  local conf="$1"
  # Extract the first `server host:port;` line within the `upstream` block.
  # This is intentionally simple and tailored to `nginx/securewave_preview.conf` template.
  if [[ ! -f "$conf" ]]; then
    echo ""
    return 0
  fi
  grep -E "^[[:space:]]*server[[:space:]]+[^;]+:[0-9]+;[[:space:]]*$" "$conf" | head -n 1 | sed -E 's/^.*:([0-9]+);.*$/\\1/'
}

finalize() {
  local finished_at
  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ -z "${OUT_DIR:-}" ]]; then
    return 0
  fi

  local canary_url="http://${CANARY_HOST}:${CANARY_PORT}"
  local ready_code metrics_code health_code version_code
  ready_code="$(http_code "${canary_url}/api/ready")"
  health_code="$(http_code "${canary_url}/api/health")"
  metrics_code="$(http_code "${canary_url}/metrics")"
  version_code="$(http_code "${canary_url}/version")"

  local metrics_path="${OUT_DIR}/metrics.txt"
  if [[ "${metrics_code}" == "200" ]]; then
    curl -fsS --max-time 10 "${canary_url}/metrics" >"${metrics_path}" 2>/dev/null || true
  fi

  local cpu="" mem="" rss="" fds="" threads="" profile_p95="" hs_p95=""
  if [[ -f "${metrics_path}" ]]; then
    cpu="$(grep -E "^securewave_system_cpu_percent " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    mem="$(grep -E "^securewave_system_memory_percent " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    rss="$(grep -E "^securewave_process_memory_mb " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    fds="$(grep -E "^securewave_process_open_fds " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    threads="$(grep -E "^securewave_process_threads " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    profile_p95="$(grep -E "^securewave_profile_issue_latency_p95_ms " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
    hs_p95="$(grep -E "^securewave_handshake_latency_p95_ms " "${metrics_path}" | awk '{print $2}' | tail -n 1 || true)"
  fi

  local pid=""
  if [[ -n "${PID_FILE:-}" && -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  fi

  # Optional alert-gating output (best-effort).
  local alert_json="${OUT_DIR}/alert_gating.json"
  local alert_md="${OUT_DIR}/alert_gating.md"
  local alert_status="skipped"
  if [[ -f "${alert_json}" ]]; then
    alert_status="$(python3 - <<PY 2>/dev/null
import json
from pathlib import Path
p=Path("${alert_json}")
try:
  d=json.loads(p.read_text(encoding="utf-8"))
except Exception:
  d={}
print(d.get("overall_status") or "unknown")
PY
)"
  fi

  local report_md="${OUT_DIR}/canary_report.md"
  cat >"${report_md}" <<EOF
# SecureWave Canary Report

- Run ID: \`${RUN_ID}\`
- Finished: \`${finished_at}\`
- Ref: \`${REF}\`
- Status: **${STATUS}**
- Failure reason: \`${FAIL_REASON:-none}\`

## Canary Instance

- URL: \`${canary_url}\`
- PID: \`${pid:-}\`
- Worktree: \`${WORKTREE_DIR}\`

## Health Checks

- \`GET /api/health\`: **${health_code}**
- \`GET /api/ready\`: **${ready_code}**
- \`GET /metrics\`: **${metrics_code}**
- \`GET /version\`: **${version_code}**

## Key Metrics (from /metrics)

- CPU percent: \`${cpu}\`
- Memory percent: \`${mem}\`
- RSS (MB): \`${rss}\`
- Open FDs: \`${fds}\`
- Threads: \`${threads}\`
- Profile P95 (ms): \`${profile_p95}\`
- Handshake P95 (ms): \`${hs_p95}\`

## Alert Gating

- Status: **${alert_status}**
- JSON: \`${alert_json}\`
- MD: \`${alert_md}\`

## Logs

- Gunicorn stdout: \`${OUT_DIR}/gunicorn_stdout.log\`
- Gunicorn access: \`${OUT_DIR}/access.log\`
- Gunicorn error: \`${OUT_DIR}/error.log\`
EOF

  # Update "latest" pointers for operators/CI.
  cp "${report_md}" "${ROOT_DIR}/artifacts/canary_report.md" 2>/dev/null || true
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --canary-host) CANARY_HOST="$2"; shift 2 ;;
    --canary-port) CANARY_PORT="$2"; shift 2 ;;
    --promote) PROMOTE="true"; shift ;;
    --nginx-conf) NGINX_CONF="$2"; shift 2 ;;
    --stabilize-seconds) STABILIZE_SECONDS="$2"; shift 2 ;;
    --stop-after-checks) STOP_AFTER_CHECKS="true"; shift ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

require_cmd git
require_cmd curl
require_cmd python3

if [[ ! "${CANARY_PORT}" =~ ^[0-9]+$ ]]; then
  die "invalid --canary-port: ${CANARY_PORT}"
fi

short_sha="$(git -C "${ROOT_DIR}" rev-parse --short "${REF}" 2>/dev/null || true)"
if [[ -z "${short_sha}" ]]; then
  die "unable to resolve git ref: ${REF}"
fi
if [[ -z "${RUN_ID}" ]]; then
  RUN_ID="$(date -u +"%Y%m%d_%H%M%S")_${short_sha}"
fi

OUT_DIR="${ROOT_DIR}/artifacts/canary/${RUN_ID}"
mkdir -p "${OUT_DIR}"
PID_FILE="${OUT_DIR}/canary.pid"

if port_in_use "${CANARY_HOST}" "${CANARY_PORT}"; then
  die "port already in use: ${CANARY_HOST}:${CANARY_PORT}"
fi

mkdir -p "${WORKTREE_ROOT}"
WORKTREE_DIR="${WORKTREE_ROOT}/${RUN_ID}"

echo "run_id=${RUN_ID}"
echo "ref=${REF} sha=${short_sha}"
echo "worktree=${WORKTREE_DIR}"
echo "canary_bind=${CANARY_HOST}:${CANARY_PORT}"
echo "out_dir=${OUT_DIR}"

echo "1) Create git worktree..."
git -C "${ROOT_DIR}" worktree add --detach "${WORKTREE_DIR}" "${REF}" >"${OUT_DIR}/git_worktree.log" 2>&1 \
  || die "git worktree add failed (see ${OUT_DIR}/git_worktree.log)"

echo "2) Create venv + install dependencies..."
VENV_DIR="${WORKTREE_DIR}/.venv"
python3 -m venv "${VENV_DIR}" >"${OUT_DIR}/venv.log" 2>&1 || die "venv creation failed"
"${VENV_DIR}/bin/pip" install --no-input --upgrade pip setuptools wheel >>"${OUT_DIR}/venv.log" 2>&1 || die "pip bootstrap failed"

REQ_FILE="${WORKTREE_DIR}/requirements_production.txt"
if [[ ! -f "${REQ_FILE}" ]]; then
  REQ_FILE="${WORKTREE_DIR}/requirements.txt"
fi
"${VENV_DIR}/bin/pip" install --no-input -r "${REQ_FILE}" >>"${OUT_DIR}/venv.log" 2>&1 || die "pip install failed (see ${OUT_DIR}/venv.log)"

echo "3) Start canary gunicorn..."
GUNICORN_BIN="${VENV_DIR}/bin/gunicorn"
[[ -x "${GUNICORN_BIN}" ]] || die "gunicorn not found in venv"

CANARY_URL="http://${CANARY_HOST}:${CANARY_PORT}"

(
  cd "${WORKTREE_DIR}"
  export APP_VERSION="${APP_VERSION:-canary-${RUN_ID}}"
  export GIT_SHA="${GIT_SHA:-$(git -C "${WORKTREE_DIR}" rev-parse HEAD 2>/dev/null || true)}"
  export ENVIRONMENT="${ENVIRONMENT:-production}"
  # Never force TESTING on in ops scripts.
  unset TESTING || true

  # Run gunicorn in the background; it will write the master pid to PID_FILE.
  nohup "${GUNICORN_BIN}" -k uvicorn.workers.UvicornWorker main:app \
    --bind "${CANARY_HOST}:${CANARY_PORT}" \
    --workers "${CANARY_WORKERS}" \
    --timeout 180 \
    --graceful-timeout 60 \
    --keep-alive 5 \
    --pid "${PID_FILE}" \
    --access-logfile "${OUT_DIR}/access.log" \
    --error-logfile "${OUT_DIR}/error.log" \
    --log-level "info" \
    >"${OUT_DIR}/gunicorn_stdout.log" 2>&1 &
) || die "failed to start gunicorn"

echo "4) Health + metrics validation..."
wait_http_200 "${CANARY_URL}/api/ready" "${CANARY_TIMEOUT_SECONDS}" \
  || die "canary did not become ready within ${CANARY_TIMEOUT_SECONDS}s (see ${OUT_DIR}/error.log)"
wait_http_200 "${CANARY_URL}/metrics" 20 || die "canary /metrics not reachable"

# Optional alert gating (only meaningful when auth is provided).
echo "5) Optional alert gating..."
if [[ -n "${ALERT_API_TOKEN:-}" || ( -n "${ALERT_API_EMAIL:-}" && -n "${ALERT_API_PASSWORD:-}" ) ]]; then
  set +e
  python3 "${ROOT_DIR}/sandbox/live_hetzner/alerting/check_alerts.py" \
    --api-base-url "${CANARY_URL}" \
    --window-seconds 10 \
    --out-json "${OUT_DIR}/alert_gating.json" \
    --out-md "${OUT_DIR}/alert_gating.md" \
    >"${OUT_DIR}/alert_gating.log" 2>&1
  alert_rc=$?
  set -e
  if [[ $alert_rc -ne 0 ]]; then
    die "alert gating failed (see ${OUT_DIR}/alert_gating.md)"
  fi
else
  echo '{"overall_status":"skipped","detail":"no ALERT_API_TOKEN or ALERT_API_EMAIL/PASSWORD"}' >"${OUT_DIR}/alert_gating.json"
  cat >"${OUT_DIR}/alert_gating.md" <<'MD'
# Alert gating skipped

No API token provided.
MD
fi

if [[ "${PROMOTE}" == "true" ]]; then
  echo "6) Promote canary (switch Nginx upstream)..."
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "--promote requires root (sudo) to edit ${NGINX_CONF} and reload nginx"
  fi

  old_port="$(extract_nginx_upstream_port "${NGINX_CONF}")"
  echo "${old_port}" >"${OUT_DIR}/old_upstream_port.txt"

  bash "${ROOT_DIR}/scripts/ops/nginx_switch_upstream.sh" --port "${CANARY_PORT}" --conf "${NGINX_CONF}" \
    >"${OUT_DIR}/nginx_switch.log" 2>&1 || die "nginx upstream switch failed (see ${OUT_DIR}/nginx_switch.log)"

  echo "7) Stabilize window (${STABILIZE_SECONDS}s) ..."
  sleep "$(python3 - <<PY
import sys
try:
  n=int("${STABILIZE_SECONDS}")
except Exception:
  n=20
print(max(0,n))
PY
)"

  # Re-run minimal checks after promotion. Roll back on breach.
  if ! wait_http_200 "${CANARY_URL}/api/ready" 10; then
    if [[ -n "${old_port}" ]]; then
      bash "${ROOT_DIR}/scripts/ops/nginx_switch_upstream.sh" --port "${old_port}" --conf "${NGINX_CONF}" \
        >>"${OUT_DIR}/nginx_switch.log" 2>&1 || true
    fi
    die "post-promotion readiness check failed; rolled back to old upstream port ${old_port}"
  fi
fi

STATUS="pass"
finalize || true

echo ""
echo "OK: canary validation passed"
echo "- Report: ${OUT_DIR}/canary_report.md"
echo "- Latest: ${ROOT_DIR}/artifacts/canary_report.md"
echo "- Canary URL: ${CANARY_URL}"
if [[ "${PROMOTE}" == "true" ]]; then
  echo "- Nginx upstream switched to port: ${CANARY_PORT}"
else
  echo "- Not promoted (run with --promote to switch Nginx upstream)"
fi

# Cleanup depending on operator intent.
cleanup || true
exit 0
