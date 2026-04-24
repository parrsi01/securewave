#!/usr/bin/env bash
###############################################################################
# SECUREWAVE VPN - LOCAL RUNTIME ENTRYPOINT
###############################################################################

set -euo pipefail

APP_PORT="${PORT:-8000}"
VENV_DIR="${VENV_DIR:-venv}"

log_info() { echo "[info] $1"; }
log_error() { echo "[error] $1" >&2; }

generate_local_database() {
  python3 - <<'PY'
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection, wireguard_peer

base.Base.metadata.create_all(bind=engine)
print("Database tables ready")
PY
}

run_local() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required"
    exit 1
  fi

  if [ ! -d "${VENV_DIR}" ]; then
    log_info "Creating virtual environment at ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
  fi

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  log_info "Installing backend dependencies"
  python -m pip install --upgrade pip
  python -m pip install -r requirements.txt

  log_info "Preparing local database"
  generate_local_database

  if [ "${SEED_DEMO_SERVERS:-true}" = "true" ]; then
    log_info "Seeding demo VPN servers"
    python infrastructure/init_demo_servers.py || true
  fi

  log_info "Starting SecureWave backend on http://localhost:${APP_PORT}"
  exec uvicorn main:app --reload --host 0.0.0.0 --port "${APP_PORT}"
}

show_help() {
  cat <<EOF
Usage: $0 [local|dev|hetzner|production|help]

Modes:
  local, dev     Start the local FastAPI backend.
  hetzner        Print the supported production runbook entrypoint.
  production     Print the supported production runbook entrypoint.
  help           Show this help text.

Production provisioning is managed through docs/HETZNER_RUNBOOK.md and
infrastructure/hetzner/.
EOF
}

case "${1:-local}" in
  local|dev)
    run_local
    ;;
  hetzner|production|prod)
    show_help
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown mode: $1"
    show_help
    exit 1
    ;;
esac
