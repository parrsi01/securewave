#!/usr/bin/env python3
"""Test script to verify imports work correctly"""

import sys
import traceback

def test_import(module_name):
    """Test importing a module"""
    try:
        __import__(module_name)
        print(f"✓ {module_name}")
        return True
    except Exception as e:
        print(f"✗ {module_name}: {e}")
        traceback.print_exc()
        return False

print("Testing imports...")
print("=" * 60)

# Test basic imports
modules = [
    "database.session",
    "models.user",
    "models.subscription",
    "services.jwt_service",
    "services.hashing_service",
    "services.auth_service",
    "routes.auth",
    "routes.billing",
    "routers.vpn",
]

all_passed = True
for module in modules:
    if not test_import(module):
        all_passed = False

print("=" * 60)
if all_passed:
    print("All imports successful! Trying to import main...")
    try:
        import main
        print("✓ main.py imported successfully!")
    except Exception as e:
        print(f"✗ main.py import failed: {e}")
        traceback.print_exc()
else:
    print("Some imports failed. Fix these first before importing main.")
