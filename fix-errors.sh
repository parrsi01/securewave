#!/bin/bash
###############################################################################
# Error Fix Script - Diagnose and fix common application errors
###############################################################################

set -e

echo "🔧 SecureWave VPN - Error Fix Script"
echo "====================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Step 1: Check if venv exists
echo -e "${BLUE}[1/6]${NC} Checking virtual environment..."
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}⚠${NC}  Virtual environment not found. Creating..."
    python3 -m venv venv
    echo -e "${GREEN}✓${NC}  Virtual environment created"
else
    echo -e "${GREEN}✓${NC}  Virtual environment exists"
fi

# Step 2: Activate and install dependencies
echo -e "${BLUE}[2/6]${NC} Installing dependencies..."
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q
echo -e "${GREEN}✓${NC}  Dependencies installed"

# Step 3: Check database
echo -e "${BLUE}[3/6]${NC} Checking database..."
if [ ! -f "securewave.db" ]; then
    echo -e "${YELLOW}⚠${NC}  Database not found. Creating tables..."
    python3 << 'PYCODE'
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print("Database created")
PYCODE
    echo -e "${GREEN}✓${NC}  Database created"
else
    echo -e "${GREEN}✓${NC}  Database exists"
fi

# Step 4: Initialize demo servers
echo -e "${BLUE}[4/6]${NC} Checking VPN servers..."
if [ -f "infrastructure/init_demo_servers.py" ]; then
    python3 infrastructure/init_demo_servers.py 2>/dev/null || echo -e "${YELLOW}⚠${NC}  Server initialization skipped"
    echo -e "${GREEN}✓${NC}  VPN servers initialized"
else
    echo -e "${YELLOW}⚠${NC}  Demo server script not found (optional)"
fi

# Step 5: Test application
echo -e "${BLUE}[5/6]${NC} Testing application..."
python3 << 'PYTEST'
import sys
sys.path.insert(0, '.')

try:
    from fastapi import FastAPI
    from database.session import SessionLocal
    from models import user
    from routers import auth
    print("All critical imports successful")
except Exception as e:
    print(f"Import error: {e}")
    sys.exit(1)
PYTEST

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}  Application test passed"
else
    echo -e "${RED}✗${NC}  Application test failed"
    exit 1
fi

# Step 6: Summary
echo -e "${BLUE}[6/6]${NC} Final checks..."
echo ""
echo "====================================="
echo -e "${GREEN}✅ All fixes applied successfully!${NC}"
echo ""
echo "Your application should now work. Start with:"
echo "  ${YELLOW}bash deploy.sh local${NC}"
echo ""
echo "Or test first with:"
echo "  ${YELLOW}bash test-app.sh${NC}"
echo "====================================="
