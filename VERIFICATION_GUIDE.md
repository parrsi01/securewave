# SecureWave Verification Guide

This document provides commands to verify the SecureWave platform is correctly configured and buildable.

## Prerequisites

- **Backend**: Python 3.11+, PostgreSQL (for production), Redis (optional)
- **Flutter App**: Flutter 3.38+ (stable channel)
- **iOS Development**: macOS with Xcode 14+, Apple Developer account
- **Android Development**: Android SDK, Java 17+

## Backend Verification

### 1. Install dependencies

```bash
cd /path/to/securewave
pip install -r requirements.txt
```

### 2. Run backend (development mode)

```bash
# Set required environment variables
export DATABASE_URL="sqlite:///./data/securewave.db"
export DEMO_MODE="true"
export WG_MOCK_MODE="true"

# Start the server
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

### 3. Verify health endpoints

```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/health
```

Expected: `{"status":"ok","service":"securewave-vpn-demo"}`

## Website Verification

### 1. Serve static files

After starting the backend, visit:

```
http://localhost:8000/
http://localhost:8000/home.html
http://localhost:8000/login.html
http://localhost:8000/register.html
```

### 2. Verify UI version

All HTML pages should include:

```html
<meta name="ui-version" content="UI_VERSION v1.0">
<link rel="stylesheet" href="/css/web_ui_v1.css?v=...">
```

### 3. Verify download links

All download sections should point to:

```
https://github.com/parrsi01/securewave/releases
```

iOS should show "Coming soon" (disabled button).

## Flutter App Verification

### 1. Install dependencies

```bash
cd securewave_app
flutter pub get
```

### 2. Run static analysis

```bash
flutter analyze
```

Expected: No errors (deprecation warnings are acceptable).

### 3. Run tests

```bash
flutter test
```

### 4. Build for platforms

#### Linux (requires Linux host)

```bash
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/`

#### Windows (requires Windows host)

```bash
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/`

#### macOS (requires macOS host)

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/securewave_app.app`

**Note**: macOS VPN requires additional setup. See [MACOS_VPN_SETUP.md](securewave_app/MACOS_VPN_SETUP.md).

#### Android

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

**Note**: Release builds require signing configuration in `android/app/build.gradle.kts`.

#### iOS (requires macOS + Xcode)

```bash
flutter build ios --release --no-codesign
```

**IMPORTANT**: See [IOS_VPN_SETUP.md](securewave_app/IOS_VPN_SETUP.md) for required Xcode steps.
You MUST use `Runner.xcworkspace`, not `Runner.xcodeproj`.

### 5. Verify mock API is disabled in release

Build with release mode and check logs should show mock API is false:

```bash
flutter build linux --release --dart-define=SECUREWAVE_USE_MOCK_API=false
# Check the config loading in app logs
```

In debug mode, mock API defaults to `true`. In release/profile, it defaults to `false` unless explicitly overridden.

## CI/CD Verification

### 1. Lint and format checks

```bash
# Backend Python linting (if tools installed)
black --check . --exclude '/(\.git|\.venv|node_modules|securewave_app)/'
isort --check-only . --skip securewave_app --skip .git
flake8 . --count --select=E9,F63,F7,F82 --exclude=securewave_app,.git
```

### 2. UI version guard

```bash
bash scripts/verify_ui_v1.sh
```

Expected: Script exits with 0 (success).

### 3. Plan copy consistency

```bash
bash scripts/check_plan_copy.sh
```

Expected: All plan pricing is consistent across pages.

## Platform-Specific Setup Docs

- **iOS VPN**: [securewave_app/IOS_VPN_SETUP.md](securewave_app/IOS_VPN_SETUP.md)
- **macOS VPN**: [securewave_app/MACOS_VPN_SETUP.md](securewave_app/MACOS_VPN_SETUP.md)
- **Windows VPN**: [securewave_app/WINDOWS_VPN_SETUP.md](securewave_app/WINDOWS_VPN_SETUP.md)

## Known Limitations

1. **iOS**: Requires Xcode for signing and capabilities setup (cannot be automated)
2. **Android**: Stub VPN service (notifications only, no tunnel)
3. **macOS/Windows**: Return `vpn_not_configured` errors with actionable guidance
4. **Backend Tests**: Require `pytest` and database setup (see `.github/workflows/ci-cd.yml`)

## Deterministic Builds

- Flutter app uses compile-time constants for build mode detection
- Mock API defaults to `false` in release unless `SECUREWAVE_USE_MOCK_API=true`
- All HTML timestamps and cache busting injected during CI build step
- Zone initialization in `main.dart` ensures deterministic error handling

## Quick Smoke Test

```bash
# Backend
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000 &
sleep 3
curl -f http://localhost:8000/health || echo "Backend health check failed"

# Flutter (Linux example)
cd securewave_app
flutter build linux --release
ls -la build/linux/x64/release/bundle/securewave_app || echo "Linux build failed"
```

## Troubleshooting

- **"No module named pytest"**: Install dev dependencies: `pip install -r requirements_dev.txt`
- **Flutter build fails**: Run `flutter doctor` and resolve any missing dependencies
- **iOS build fails**: Ensure you're using `Runner.xcworkspace` in Xcode, not `Runner.xcodeproj`
- **Mock API in production**: Verify `--release` build mode and check compile-time constants
