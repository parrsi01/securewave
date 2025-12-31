#!/usr/bin/env bash
set -e

echo "================================================"
echo "SecureWave Deployment Validation"
echo "================================================"
echo ""

ERRORS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
    else
        echo -e "${RED}✗${NC} $1 MISSING"
        ((ERRORS++))
    fi
}

check_executable() {
    if [ -x "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 is executable"
    else
        echo -e "${RED}✗${NC} $1 NOT executable"
        ((ERRORS++))
    fi
}

echo "Checking critical files..."
echo ""

# Core application files
check_file "main.py"
check_file "requirements.txt"
check_file "Dockerfile"

echo ""
echo "Checking deployment files..."
echo ""

check_file "deploy/nginx.conf"
check_file "deploy/entrypoint.sh"
check_file "deploy_securewave_option1_container.sh"
check_executable "deploy/entrypoint.sh"
check_executable "deploy_securewave_option1_container.sh"

echo ""
echo "Checking routers..."
echo ""

check_file "routers/auth.py"
check_file "routers/vpn.py"
check_file "routers/optimizer.py"
check_file "routers/dashboard.py"
check_file "routers/payment_stripe.py"
check_file "routers/payment_paypal.py"

echo ""
echo "Checking services..."
echo ""

check_file "services/wireguard_service.py"
check_file "services/vpn_optimizer.py"
check_file "services/jwt_service.py"
check_file "services/stripe_service.py"

echo ""
echo "Checking models and database..."
echo ""

check_file "models/user.py"
check_file "models/subscription.py"
check_file "database/session.py"

echo ""
echo "Checking frontend..."
echo ""

if [ -d "frontend" ]; then
    echo -e "${GREEN}✓${NC} frontend/ directory exists"
    if [ -f "frontend/index.html" ]; then
        echo -e "${GREEN}✓${NC} frontend/index.html exists"
    else
        echo -e "${RED}✗${NC} frontend/index.html MISSING"
        ((ERRORS++))
    fi
else
    echo -e "${RED}✗${NC} frontend/ directory MISSING"
    ((ERRORS++))
fi

echo ""
echo "Checking documentation..."
echo ""

check_file "DEPLOYMENT.md"
check_file "FIXES_SUMMARY.md"

echo ""
echo "Validating requirements.txt..."
echo ""

if grep -q "uvicorn\[standard\]" requirements.txt; then
    echo -e "${GREEN}✓${NC} uvicorn[standard] found in requirements.txt"
else
    echo -e "${RED}✗${NC} uvicorn[standard] MISSING in requirements.txt"
    ((ERRORS++))
fi

if grep -q "gunicorn" requirements.txt; then
    echo -e "${GREEN}✓${NC} gunicorn found in requirements.txt"
else
    echo -e "${RED}✗${NC} gunicorn MISSING in requirements.txt"
    ((ERRORS++))
fi

if grep -q "xgboost" requirements.txt; then
    echo -e "${GREEN}✓${NC} xgboost found in requirements.txt (VPN optimizer)"
else
    echo -e "${RED}✗${NC} xgboost MISSING in requirements.txt"
    ((ERRORS++))
fi

if grep -q "stripe>=14" requirements.txt; then
    echo -e "${GREEN}✓${NC} stripe>=14.0.0 (Python 3.12 compatible)"
else
    echo -e "${YELLOW}⚠${NC} stripe version may be incompatible with Python 3.12"
fi

echo ""
echo "Validating main.py..."
echo ""

if grep -q "prefix=\"/api" main.py; then
    echo -e "${GREEN}✓${NC} API routes prefixed with /api"
else
    echo -e "${RED}✗${NC} API routes NOT properly prefixed"
    ((ERRORS++))
fi

if grep -q "optimizer.router" main.py; then
    echo -e "${GREEN}✓${NC} Optimizer router included"
else
    echo -e "${RED}✗${NC} Optimizer router NOT included"
    ((ERRORS++))
fi

# Check for double static mount (should NOT exist)
STATIC_MOUNTS=$(grep -c "app.mount.*StaticFiles" main.py || true)
if [ "$STATIC_MOUNTS" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Single StaticFiles mount (no conflicts)"
elif [ "$STATIC_MOUNTS" -eq 0 ]; then
    echo -e "${YELLOW}⚠${NC} No StaticFiles mount found"
else
    echo -e "${RED}✗${NC} Multiple StaticFiles mounts detected (will cause conflicts!)"
    ((ERRORS++))
fi

echo ""
echo "Validating Dockerfile..."
echo ""

if grep -q "python:3.12" Dockerfile; then
    echo -e "${GREEN}✓${NC} Python 3.12 base image"
else
    echo -e "${YELLOW}⚠${NC} Not using Python 3.12"
fi

if grep -q "nginx" Dockerfile; then
    echo -e "${GREEN}✓${NC} Nginx installed in Docker image"
else
    echo -e "${RED}✗${NC} Nginx NOT in Dockerfile"
    ((ERRORS++))
fi

if grep -q "EXPOSE 8080" Dockerfile; then
    echo -e "${GREEN}✓${NC} Port 8080 exposed (Azure requirement)"
else
    echo -e "${RED}✗${NC} Port 8080 NOT exposed"
    ((ERRORS++))
fi

echo ""
echo "Validating nginx.conf..."
echo ""

if grep -q "listen 8080" deploy/nginx.conf; then
    echo -e "${GREEN}✓${NC} Nginx listening on port 8080"
else
    echo -e "${RED}✗${NC} Nginx NOT listening on 8080"
    ((ERRORS++))
fi

if grep -q "location /api/" deploy/nginx.conf; then
    echo -e "${GREEN}✓${NC} API proxy location configured"
else
    echo -e "${RED}✗${NC} API proxy NOT configured"
    ((ERRORS++))
fi

if grep -q "proxy_pass.*backend" deploy/nginx.conf; then
    echo -e "${GREEN}✓${NC} Backend proxy configured"
else
    echo -e "${RED}✗${NC} Backend proxy NOT configured"
    ((ERRORS++))
fi

echo ""
echo "Validating entrypoint.sh..."
echo ""

if grep -q "gunicorn" deploy/entrypoint.sh; then
    echo -e "${GREEN}✓${NC} Gunicorn startup configured"
else
    echo -e "${RED}✗${NC} Gunicorn NOT in entrypoint"
    ((ERRORS++))
fi

if grep -q "uvicorn.workers.UvicornWorker" deploy/entrypoint.sh; then
    echo -e "${GREEN}✓${NC} Uvicorn worker class specified"
else
    echo -e "${RED}✗${NC} Uvicorn worker NOT specified"
    ((ERRORS++))
fi

if grep -q "127.0.0.1:8000" deploy/entrypoint.sh; then
    echo -e "${GREEN}✓${NC} Gunicorn binding to 127.0.0.1:8000"
else
    echo -e "${YELLOW}⚠${NC} Gunicorn binding may be incorrect"
fi

echo ""
echo "Checking Azure CLI..."
echo ""

if command -v az &> /dev/null; then
    echo -e "${GREEN}✓${NC} Azure CLI installed"
    if az account show &> /dev/null; then
        echo -e "${GREEN}✓${NC} Azure CLI authenticated"
    else
        echo -e "${YELLOW}⚠${NC} Not logged into Azure (run: az login)"
    fi
else
    echo -e "${RED}✗${NC} Azure CLI NOT installed"
    ((ERRORS++))
fi

echo ""
echo "================================================"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
    echo ""
    echo "Ready to deploy! Run:"
    echo "  ./deploy_securewave_option1_container.sh"
    exit 0
else
    echo -e "${RED}✗ $ERRORS ERROR(S) FOUND${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi
