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
#   SSH in → systemctl restart securewave-api
#   or: systemctl stop securewave-api; git -C /opt/securewave checkout <prev-sha>
#       systemctl start securewave-api
set -euo pipefail

VPS_HOST="${VPS_HOST:-138.199.204.139}"
VPS_USER="${VPS_USER:-securewave}"
APP_DIR="${APP_DIR:-/opt/securewave}"
VENV_DIR="${VENV_DIR:-$APP_DIR/.venv}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SSH_OPTS=(-o StrictHostKeyChecking=no)
if [[ -n "$SSH_KEY_PATH" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY_PATH")
fi

ssh_exec() { ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" "$@"; }
scp_file() { scp "${SSH_OPTS[@]}" "$1" "${VPS_USER}@${VPS_HOST}:$2"; }

echo "==> [1/7] Verifying VPS reachability"
ssh_exec "echo VPS_OK"

echo "==> [1b/7] Checking production env for REDIS_URL"
# Multi-worker rate limiting requires Redis. Without it, each Gunicorn worker
# has an independent in-memory rate limit counter — silently allowing N×limit
# requests with N workers. Set REDIS_URL in /etc/securewave/env for production.
if ssh_exec "grep -q '^REDIS_URL=' /etc/securewave/env 2>/dev/null"; then
    echo "  REDIS_URL: present"
else
    echo "  WARNING: REDIS_URL is not set in /etc/securewave/env"
    echo "  Rate limiting will be per-process (ineffective with multiple Gunicorn workers)."
    echo "  To fix: add REDIS_URL=redis://127.0.0.1:6379/0 to /etc/securewave/env"
fi

echo "==> [2/7] Syncing application code"
# rsync excludes: venv, __pycache__, .git, secrets, test artifacts
rsync -az --delete \
    --exclude='.git' \
    --exclude='venv/' \
    --exclude='.venv/' \
    --exclude='.env' \
    --exclude='.env.production' \
    --exclude='.env.hetzner' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.sqlite' \
    --exclude='*.db' \
    --exclude='securewave_private/' \
    --exclude='tools/egress_proof/out' \
    --exclude='tools/live_debugger/out' \
    --exclude='tools/outage_recovery/out' \
    --exclude='securewave_app/' \
    -e "ssh ${SSH_OPTS[*]}" \
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
    # Verify env file exists and has secure permissions (600 = owner read/write only)
    test -f /etc/securewave/env || { echo 'ERROR: /etc/securewave/env not found'; exit 1; }
    actual_perms=\$(stat -c '%a' /etc/securewave/env)
    if [[ \"\$actual_perms\" != '600' ]]; then
        echo \"WARNING: /etc/securewave/env has permissions \$actual_perms, enforcing 600\"
        sudo chmod 600 /etc/securewave/env
        sudo chown root:root /etc/securewave/env
    fi
    set -a
    source /etc/securewave/env
    set +a
    $VENV_DIR/bin/python -m alembic upgrade head
"

echo "==> [5/7] Installing systemd units"
for unit in securewave-api.service securewave-watchdog.service securewave-watchdog.timer securewave-db-maintenance.service securewave-db-maintenance.timer; do
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
    sudo systemctl disable --now securewave.service 2>/dev/null || true
    sudo systemctl disable --now securewave-backend.service 2>/dev/null || true
    sudo systemctl enable --now securewave-api
    sudo systemctl restart securewave-api
    sudo systemctl enable --now securewave-watchdog.timer
    sudo systemctl enable --now securewave-db-maintenance.timer
    sleep 3
    sudo systemctl is-active securewave-api
"

echo "==> [7/7] Smoke test"
if ! ssh_exec "curl -fsS http://127.0.0.1:8080/api/health >/dev/null"; then
    echo "  direct HTTP health check failed, trying HTTPS edge"
    ssh_exec "curl -fsSk https://127.0.0.1/api/health >/dev/null"
fi
ssh_exec "echo 'Backend health: OK'"

echo ""
echo "Deploy complete. Backend is live on ${VPS_HOST}:8080"
echo "Logs: ssh ${VPS_USER}@${VPS_HOST} journalctl -u securewave-api -f"
echo "Watchdog: ssh ${VPS_USER}@${VPS_HOST} journalctl -u securewave-watchdog -f"
echo ""
echo "REMINDER: nginx config is NOT auto-deployed here."
echo "  To deploy/refresh nginx (requires domain + certs):"
echo "  bash scripts/setup_tls_certbot.sh --domain <apex> --domain <www> --email <ops@email>"
