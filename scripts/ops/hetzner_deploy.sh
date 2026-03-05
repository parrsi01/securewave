#!/usr/bin/env bash
# SecureWave — Hetzner VPS full deploy / redeploy script.
#
# Installs or updates the backend + all systemd units on the VPS.
# Run from your local machine (not inside the VPS).
#
# Prerequisites on VPS:
#   - Ubuntu 22.04+
#   - SSH key auth as root or securewave user with sudo
#   - hetzner_bootstrap.sh already run once
#
# Usage:
#   VPS_HOST=138.199.204.139 bash scripts/ops/hetzner_deploy.sh
#
# Rollback:
#   SSH in → systemctl restart securewave-backend
#   or: systemctl stop securewave-backend; git -C /opt/securewave checkout <prev-sha>
#       systemctl start securewave-backend
set -euo pipefail

VPS_HOST="${VPS_HOST:-138.199.204.139}"
VPS_USER="${VPS_USER:-securewave}"
APP_DIR="/opt/securewave"
VENV_DIR="$APP_DIR/venv"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ssh_exec() { ssh -o StrictHostKeyChecking=no "${VPS_USER}@${VPS_HOST}" "$@"; }
scp_file() { scp -o StrictHostKeyChecking=no "$1" "${VPS_USER}@${VPS_HOST}:$2"; }

echo "==> [1/7] Verifying VPS reachability"
ssh_exec "echo VPS_OK"

echo "==> [2/7] Syncing application code"
# rsync excludes: venv, __pycache__, .git, secrets, test artifacts
rsync -az --delete \
    --exclude='.git' \
    --exclude='venv/' \
    --exclude='.venv/' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.sqlite' \
    --exclude='*.db' \
    --exclude='tools/egress_proof/out' \
    --exclude='tools/live_debugger/out' \
    --exclude='tools/outage_recovery/out' \
    --exclude='securewave_app/' \
    -e "ssh -o StrictHostKeyChecking=no" \
    "$REPO_ROOT/" "${VPS_USER}@${VPS_HOST}:${APP_DIR}/"

echo "==> [3/7] Installing Python dependencies"
ssh_exec "
    set -euo pipefail
    cd $APP_DIR
    [[ -d $VENV_DIR ]] || python3 -m venv $VENV_DIR
    $VENV_DIR/bin/pip install --upgrade pip -q
    $VENV_DIR/bin/pip install -r requirements.txt -q
"

echo "==> [4/7] Running DB migrations"
ssh_exec "
    set -euo pipefail
    cd $APP_DIR
    source /etc/securewave/env
    $VENV_DIR/bin/python -m alembic upgrade head 2>/dev/null || \
        $VENV_DIR/bin/python -c '
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print(\"DB tables ready\")
'
"

echo "==> [5/7] Installing systemd units"
for unit in securewave-backend.service securewave-watchdog.service securewave-watchdog.timer securewave-db-maintenance.service securewave-db-maintenance.timer; do
    local_file="$REPO_ROOT/infrastructure/systemd/$unit"
    [[ -f "$local_file" ]] || { echo "SKIP: $unit not found"; continue; }
    scp_file "$local_file" "/tmp/$unit"
    ssh_exec "sudo mv /tmp/$unit /etc/systemd/system/$unit && sudo chmod 644 /etc/systemd/system/$unit"
done

ssh_exec "sudo systemctl daemon-reload"

echo "==> [6/7] Installing logrotate config and enabling services"
# Logrotate
LOGROTATE_SRC="$REPO_ROOT/infrastructure/logrotate/securewave"
if [[ -f "$LOGROTATE_SRC" ]]; then
    scp_file "$LOGROTATE_SRC" "/tmp/securewave-logrotate"
    ssh_exec "sudo mv /tmp/securewave-logrotate /etc/logrotate.d/securewave && sudo chmod 644 /etc/logrotate.d/securewave"
    echo "  logrotate config installed"
fi

# Systemd services
ssh_exec "
    sudo systemctl enable --now securewave-backend
    sudo systemctl restart securewave-backend
    sudo systemctl enable --now securewave-watchdog.timer
    sudo systemctl enable --now securewave-db-maintenance.timer
    sleep 3
    sudo systemctl is-active securewave-backend
"

echo "==> [7/7] Smoke test"
ssh_exec "curl -fsS http://127.0.0.1:8080/health && echo 'Backend health: OK'"

echo ""
echo "Deploy complete. Backend is live on ${VPS_HOST}:8080"
echo "Logs: ssh ${VPS_USER}@${VPS_HOST} journalctl -u securewave-backend -f"
echo "Watchdog: ssh ${VPS_USER}@${VPS_HOST} journalctl -u securewave-watchdog -f"
echo ""
echo "REMINDER: nginx config is NOT auto-deployed here."
echo "  To deploy/refresh nginx (requires domain + certs):"
echo "  SERVER_NAME=<domain> SSL_CERT=<path> SSL_KEY=<path> bash scripts/ops/render_nginx_conf.sh"
