#!/bin/bash
###############################################################################
# Quick Application Test Script
# Tests if the app can start without errors
###############################################################################

set -e

echo "🧪 SecureWave VPN - Application Test"
echo "===================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if venv exists
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}⚠${NC}  Creating virtual environment..."
    python3 -m venv venv
fi

# Activate venv
echo -e "${GREEN}✓${NC}  Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo -e "${GREEN}✓${NC}  Installing dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt -q

echo ""
echo "Testing Python imports..."
echo "-------------------------"

# Test imports
python3 << 'PYTHON_TEST'
import sys
import os

# Set up path
sys.path.insert(0, os.getcwd())

errors = []
warnings = []

# Test core imports
print("Testing core imports...")
try:
    from fastapi import FastAPI
    print("  ✓ FastAPI")
except Exception as e:
    errors.append(f"FastAPI: {e}")
    print(f"  ✗ FastAPI: {e}")

try:
    from database.session import SessionLocal
    print("  ✓ Database session")
except Exception as e:
    errors.append(f"Database: {e}")
    print(f"  ✗ Database: {e}")

try:
    from database import base
    print("  ✓ Database base")
except Exception as e:
    errors.append(f"Database base: {e}")
    print(f"  ✗ Database base: {e}")

# Test models
print("\nTesting models...")
try:
    from models import user, subscription, audit_log, vpn_server, vpn_connection
    print("  ✓ All models")
except Exception as e:
    errors.append(f"Models: {e}")
    print(f"  ✗ Models: {e}")

# Test routers
print("\nTesting routers...")
routers = ['auth', 'vpn', 'optimizer', 'dashboard', 'contact', 'payment_stripe', 'payment_paypal']
for router_name in routers:
    try:
        module = __import__(f'routers.{router_name}', fromlist=[router_name])
        print(f"  ✓ routers.{router_name}")
    except Exception as e:
        warnings.append(f"Router {router_name}: {e}")
        print(f"  ⚠ routers.{router_name}: {e}")

# Test services
print("\nTesting services...")
try:
    from services.wireguard_service import WireGuardService
    print("  ✓ WireGuard service")
except Exception as e:
    warnings.append(f"WireGuard: {e}")
    print(f"  ⚠ WireGuard service: {e}")

try:
    from services.vpn_optimizer import get_vpn_optimizer
    print("  ✓ VPN optimizer")
except Exception as e:
    warnings.append(f"VPN optimizer: {e}")
    print(f"  ⚠ VPN optimizer: {e}")

# Summary
print("\n" + "="*50)
if errors:
    print(f"\n❌ CRITICAL ERRORS ({len(errors)}):")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)
elif warnings:
    print(f"\n⚠️  WARNINGS ({len(warnings)}):")
    for warning in warnings:
        print(f"  - {warning}")
    print("\n✅ Core functionality should work, but some features may be limited")
    sys.exit(0)
else:
    print("\n✅ ALL TESTS PASSED!")
    sys.exit(0)
PYTHON_TEST

TEST_RESULT=$?

echo ""
echo "===================================="

if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Application is ready to run!${NC}"
    echo ""
    echo "Start the server with:"
    echo "  bash deploy.sh local"
    exit 0
else
    echo -e "${RED}❌ Application has errors${NC}"
    echo ""
    echo "Please check the errors above and fix them."
    echo "Then run this test again:"
    echo "  bash test-app.sh"
    exit 1
fi
