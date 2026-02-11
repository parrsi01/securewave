#!/usr/bin/env bash
###############################################################################
# SECUREWAVE VPN - LOCAL DEPLOYMENT SCRIPT
# Local dev bootstrap only. For production, see docs/HETZNER_RUNBOOK.md
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_step() { echo -e "${CYAN}▸${NC}  ${CYAN}$1${NC}"; }

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 local

Commands:
  local  Run the local development stack

Production deployment:
  See docs/HETZNER_RUNBOOK.md
EOF
}

###############################################################################
# LOCAL DEVELOPMENT MODE
###############################################################################
deploy_local() {
    print_header "SECUREWAVE VPN - LOCAL DEVELOPMENT"

    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}✗${NC}  Python 3 is required but not installed"
        exit 1
    fi

    log_info "Python version: $(python3 --version)"

    if [ ! -d "venv" ]; then
        log_step "[1/5] Creating virtual environment..."
        python3 -m venv venv
        log_success "Virtual environment created"
    else
        log_info "[1/5] Virtual environment already exists"
    fi

    log_step "[2/5] Activating virtual environment..."
    source venv/bin/activate
    log_success "Virtual environment activated"

    log_step "[3/5] Installing dependencies..."
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    log_success "Dependencies installed"

    log_step "[4/5] Setting up database..."
    python3 - <<'PY'
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print('Database tables ready')
PY
    log_success "Database ready"

    if [ -f "infrastructure/init_demo_servers.py" ]; then
        log_step "[5/5] Initializing demo VPN servers..."
        python3 infrastructure/init_demo_servers.py 2>/dev/null || true
        log_success "Demo servers initialized"
    fi

    print_header "SECUREWAVE VPN IS STARTING"

    echo -e "${GREEN}Your application is available at:${NC}"
    echo "  Website:      http://localhost:8000"
    echo "  Home:         http://localhost:8000/home.html"
    echo "  Login:        http://localhost:8000/login.html"
    echo "  Register:     http://localhost:8000/register.html"
    echo "  Dashboard:    http://localhost:8000/dashboard.html"
    echo "  API Docs:     http://localhost:8000/api/docs"
    echo "  Health:       http://localhost:8000/api/health"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
    echo "════════════════════════════════════════════════════════════════════════"

    exec uvicorn main:app --reload --host 0.0.0.0 --port 8000
}

case "${1:-}" in
    local|dev)
        deploy_local
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        usage
        exit 1
        ;;
esac
