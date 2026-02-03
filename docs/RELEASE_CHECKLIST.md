# SecureWave Release Checklist

Use this checklist before staging or production releases. Complete in order.

---

## 0) Release Preflight (Mandatory)

```bash
bash scripts/release_preflight.sh
```

**Expected output:**
```
OK: Release preflight checks passed.
```

---

## 1) SMTP / Email Provider

**Required env vars (pick one provider):**

| Provider | Required Variables |
|----------|-------------------|
| SMTP | `EMAIL_PROVIDER=smtp`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `FROM_EMAIL` |
| SendGrid | `EMAIL_PROVIDER=sendgrid`, `SENDGRID_API_KEY`, `FROM_EMAIL` |
| AWS SES | `EMAIL_PROVIDER=ses`, `AWS_SES_REGION`, `FROM_EMAIL` |

**Steps:**
- [ ] Pick provider and set env vars
- [ ] Validate config:
  ```bash
  bash scripts/verify_production_env.sh
  ```
- [ ] Start API and confirm email health (does NOT send email):
  ```bash
  uvicorn main:app --host 0.0.0.0 --port 8000 &
  sleep 3
  curl -f http://localhost:8000/api/health/email
  ```

---

## 2) Encryption Keys

**Generate new Fernet keys:**
```bash
bash scripts/generate_keys.sh
```

**Set in environment:**
```bash
export AUTH_ENCRYPTION_KEY="<generated-key>"
export WG_ENCRYPTION_KEY="<generated-key>"
```

**Validate (strict):**
```bash
ENVIRONMENT=production DEMO_MODE=false WG_MOCK_MODE=false \
  bash scripts/setup_production_env.sh
```

**Expected output:**
```
OK: Production environment variables validated.
```

---

## 3) Production Env Validation (CI-safe)

CI can run the safe verifier without secrets. Use strict mode when preparing a real release:

```bash
# Safe mode (warns on missing values)
bash scripts/verify_production_env.sh

# Strict mode (errors on missing values)
VERIFY_STRICT=true bash scripts/verify_production_env.sh
```

**Expected output (strict mode):**
```
Verification mode: strict
Errors: 0
Warnings: 0
```

---

## 4) Database (Production)

- [ ] Set `DATABASE_URL` (managed PostgreSQL, NOT SQLite)
  ```bash
  export DATABASE_URL="postgresql://user:pass@host:5432/securewave"
  ```
- [ ] Run migrations:
  ```bash
  alembic upgrade head
  ```
- [ ] Verify connectivity:
  ```bash
  curl -f http://localhost:8000/api/ready
  ```

---

## 5) Backend Runtime

**Required production settings:**
```bash
export ENVIRONMENT=production
export DEMO_MODE=false
export WG_MOCK_MODE=false
```

**Verify:**
```bash
# Health check
curl -f http://localhost:8000/api/health

# Email config check (no email sent)
curl -f http://localhost:8000/api/health/email

# Run smoke tests
bash scripts/run_smoke_tests.sh
```

---

## 6) iOS (Manual Xcode)

**IMPORTANT: Always use Runner.xcworkspace, never Runner.xcodeproj.**

- [ ] Open workspace:
  ```bash
  open securewave_app/ios/Runner.xcworkspace
  ```
- [ ] Enable Network Extension capability (Packet Tunnel)
- [ ] Configure signing + team for both Runner and PacketTunnel targets
- [ ] Build and validate device install

**Verify workspace guard:**
```bash
bash securewave_app/ios/scripts/ensure_workspace.sh
```

---

## 7) macOS (Stub Only)

```bash
cd securewave_app
flutter build macos --release
```

**Expected output:**
```
build/macos/Build/Products/Release/
```

**Runtime behavior:** `connect` returns `vpn_not_configured` until a macOS VPN extension is added.

---

## 8) Android (Release Signing)

- [ ] Create release keystore (if not exists):
  ```bash
  keytool -genkey -v -keystore securewave-release.jks \
    -alias securewave -keyalg RSA -keysize 2048 -validity 10000
  ```
- [ ] Configure `android/key.properties`:
  ```properties
  storeFile=securewave-release.jks
  storePassword=<password>
  keyAlias=securewave
  keyPassword=<password>
  ```
- [ ] Build release:
  ```bash
  cd securewave_app
  flutter build appbundle --release
  ```

**Expected output:**
```
build/app/outputs/bundle/release/app-release.aab
```

---

## 9) Windows Validation + Installer

```powershell
where.exe wireguard.exe
Get-Service -Name "WireGuardManager"
cd securewave_app
./scripts/build_windows_installer.ps1 -Version 4.0.0
```

**Expected output:**
```
C:\Program Files\WireGuard\wireguard.exe
OK: Built securewave_app\\build\\installer\\SecureWaveVPN-4.0.0-setup.exe
```

---

## 10) Linux Packaging (AppImage + .deb)

```bash
# Install appimage-builder (Debian/Ubuntu)
sudo apt-get install -y appimage-builder

# Build AppImage
bash securewave_app/scripts/build_appimage.sh

# Build .deb
bash securewave_app/scripts/build_deb.sh

# Test on clean system
./SecureWave-x86_64.AppImage
```

**Expected output:**
```
SecureWave-x86_64.AppImage
OK: Built securewave_app/build/packaging/securewave-vpn_<version>_<arch>.deb
```

---

## 11) Store Submissions

- [ ] App Store: screenshots, metadata, privacy labels
- [ ] Google Play: screenshots, metadata, privacy labels
- [ ] Submit builds and monitor review status

---

## Common Failures

### SMTP Configuration

**Symptom:** `/api/health/email` returns 503 or shows missing vars.

**Fix:**
```bash
# Check current config
curl http://localhost:8000/api/health/email | jq

# Set all required vars
export EMAIL_PROVIDER=smtp
export SMTP_HOST=smtp.gmail.com
export SMTP_PORT=587
export SMTP_USER=your-email@gmail.com
export SMTP_PASSWORD=your-app-password
export FROM_EMAIL=noreply@yourdomain.com
```

**Gmail App Password:**
1. Enable 2FA on Google Account
2. Go to Security > App passwords
3. Generate password for "Mail"

---

### Encryption Keys

**Symptom:** App crashes on startup with "AUTH_ENCRYPTION_KEY missing" or "invalid Fernet key".

**Fix:**
```bash
# Generate fresh keys
bash scripts/generate_keys.sh

# Set in environment (copy exact output)
export AUTH_ENCRYPTION_KEY=<key-from-output>
export WG_ENCRYPTION_KEY=<key-from-output>
```

**Verify key is valid:**
```bash
python3 -c "
from cryptography.fernet import Fernet
import os
key = os.getenv('AUTH_ENCRYPTION_KEY')
try:
    Fernet(key.encode())
    print('OK: Key is valid')
except Exception as e:
    print(f'FAIL: {e}')
"
```

---

### iOS Runner.xcworkspace Error

**Symptom:** Build fails with missing pods, CocoaPods errors, or "module not found".

**Fix:**
```bash
# 1. Close Xcode completely
# 2. Reinstall pods
cd securewave_app/ios
rm -rf Pods Podfile.lock
pod install

# 3. Open WORKSPACE (not project)
open Runner.xcworkspace
```

**Never open `Runner.xcodeproj` directly.**

---

### Database Connection Failed

**Symptom:** `/api/ready` returns "not_ready" or connection errors.

**Fix:**
```bash
# Check DATABASE_URL format
echo $DATABASE_URL
# Should be: postgresql://user:pass@host:5432/dbname

# Test connection
psql "$DATABASE_URL" -c "SELECT 1"

# Run migrations
alembic upgrade head
```

---

### Demo/Mock Mode in Production

**Symptom:** App starts but VPN connections are simulated.

**Fix:**
```bash
# Must be explicitly false
export DEMO_MODE=false
export WG_MOCK_MODE=false
export ENVIRONMENT=production

# Verify
bash scripts/verify_env.sh
```

---

### CI Test Failures

**Symptom:** pytest fails in CI but passes locally.

**Common causes:**
1. Missing `requirements_dev.txt` install
2. Database not initialized
3. Missing environment variables

**Fix:**
```bash
# Full test run with proper env
export TESTING=true
export DATABASE_URL=sqlite:///:memory:
export SECRET_KEY=test-secret-key
export DEMO_MODE=true
export WG_MOCK_MODE=true

pip install -r requirements_dev.txt
pytest tests -v
```
