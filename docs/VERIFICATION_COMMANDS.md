# SecureWave Verification Commands

Use these commands to validate the backend, website, and environment configuration.

---

## Quick Health Check (All Platforms)

```bash
# 1. Syntax check (no execution)
python -m compileall . -q

# 2. Environment validation
bash scripts/verify_env.sh

# 3. Run tests
bash scripts/run_backend_tests.sh

# 4. Website/UI verification
bash scripts/verify_website.sh
bash scripts/verify_ui_v1.sh
```

---

## Linux

### Backend Validation
```bash
# Compile check (catches syntax errors)
python3 -m compileall . -q
echo "Compile check: $?"

# Environment validation (development mode)
bash scripts/verify_env.sh

# Run full test suite
bash scripts/run_backend_tests.sh

# Run only unit tests (faster)
PYTEST_ARGS="tests/unit -v" bash scripts/run_backend_tests.sh

# Run smoke tests only
PYTEST_ARGS="tests/smoke -v" bash scripts/run_backend_tests.sh
```

### Website Validation
```bash
bash scripts/verify_website.sh
bash scripts/verify_ui_v1.sh
```

### API Health Checks
```bash
# Start API in background
uvicorn main:app --host 0.0.0.0 --port 8000 &
API_PID=$!
sleep 3

# Run checks
curl -sf http://localhost:8000/api/health && echo "OK: health"
curl -sf http://localhost:8000/api/ready && echo "OK: ready"
curl -s http://localhost:8000/api/health/email | jq .

# Stop API
kill $API_PID 2>/dev/null
```

### Linux VPN Bridge Check
```bash
# Verify the Linux runner uses the authenticated helper and the packaged
# privileged wrapper still delegates WireGuard operations to wg-quick.
grep -n "kHelperSocketPath" securewave_app/linux/runner/my_application.cc \
  && grep -n "wg-quick" securewave_app/packaging/linux/securewave-wg-quick \
  && echo "OK: Linux helper bridge and wg-quick integration found"
```

---

## macOS

### Backend Validation
```bash
# Compile check
python3 -m compileall . -q

# Environment validation
bash scripts/verify_env.sh

# Run tests
bash scripts/run_backend_tests.sh
```

### iOS Workspace Validation
```bash
# Verify workspace exists and is valid
bash securewave_app/ios/scripts/ensure_workspace.sh

# Verify CocoaPods are installed
ls -la securewave_app/ios/Pods/Pods.xcodeproj && echo "OK: Pods installed"

# Verify Go is installed (required for WireGuard build)
go version && echo "OK: Go installed"

# Open workspace (never open .xcodeproj)
open securewave_app/ios/Runner.xcworkspace
```

### iOS Build Verification (CLI, no signing)
```bash
xcodebuild -workspace securewave_app/ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### macOS Workspace Validation
```bash
bash securewave_app/macos/scripts/ensure_workspace.sh
```

---

## Windows (PowerShell)

### Backend Validation
```powershell
# Compile check
python -m compileall . -q

# Environment validation
bash scripts/verify_env.sh

# Run tests (Git Bash or WSL)
bash scripts/run_backend_tests.sh
```

### WireGuard Validation
```powershell
# Validate WireGuard installation
powershell -ExecutionPolicy Bypass -File securewave_app/scripts/validate_wireguard_windows.ps1

# Check wireguard.exe is in PATH
where.exe wireguard.exe

# Check WireGuard service
Get-Service -Name WireGuardManager -ErrorAction SilentlyContinue
```

### Windows VPN Bridge Check
```powershell
# Verify wireguard.exe integration exists
Select-String -Path "securewave_app/windows/runner/flutter_window.cpp" -Pattern "wireguard.exe"
```

---

## Production/Staging Validation

### Pre-deployment Checks
```bash
# Set production env vars
export ENVIRONMENT=production
export DEMO_MODE=false
export WG_MOCK_MODE=false

# Generate encryption keys if needed
bash scripts/generate_keys.sh

# Set keys (copy output from above)
export AUTH_ENCRYPTION_KEY="<key>"
export WG_ENCRYPTION_KEY="<key>"

# Validate ALL production requirements
bash scripts/verify_env.sh
```

### Production API Validation
```bash
# Health check
curl -sf https://your-domain.com/api/health

# Database connectivity
curl -sf https://your-domain.com/api/ready

# Email configuration (does NOT send email)
curl -s https://your-domain.com/api/health/email | jq .
```

### Release Guards Validation
```bash
# Verify all VPN bridges and release guards
bash scripts/verify_release_guards.sh
```

---

## CI Environment Setup

For GitHub Actions or other CI systems:

```yaml
env:
  TESTING: "true"
  ENVIRONMENT: "development"
  DEMO_MODE: "true"
  WG_MOCK_MODE: "true"
  DATABASE_URL: "sqlite:///:memory:"
  SECRET_KEY: "test-secret-key-for-ci"
  ACCESS_TOKEN_SECRET: "test-access-token-secret"
  REFRESH_TOKEN_SECRET: "test-refresh-token-secret"
  EMAIL_VALIDATOR_CHECK_DELIVERABILITY: "false"

steps:
  - name: Install dependencies
    run: pip install -r requirements_dev.txt

  - name: Run tests
    run: pytest tests -v --cov=. --cov-report=xml
```

---

## Troubleshooting

### "Python not found"
```bash
# Linux/macOS
which python3
python3 --version

# Windows
where.exe python
python --version
```

### "pytest not found"
```bash
pip install pytest pytest-cov pytest-asyncio
# Or use the script which installs deps:
bash scripts/run_backend_tests.sh
```

### "Database connection failed"
```bash
# Check DATABASE_URL
echo $DATABASE_URL

# Test connection (PostgreSQL)
psql "$DATABASE_URL" -c "SELECT 1"

# For testing, use SQLite
export DATABASE_URL="sqlite:///:memory:"
```

### "Encryption key invalid"
```bash
# Generate new keys
bash scripts/generate_keys.sh

# Validate a key
python3 -c "
from cryptography.fernet import Fernet
import os
key = os.getenv('AUTH_ENCRYPTION_KEY', '')
try:
    Fernet(key.encode())
    print('OK: Key is valid')
except Exception as e:
    print(f'FAIL: {e}')
"
```
