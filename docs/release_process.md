# SecureWave Release Process (Manifest-Driven)

This process publishes desktop/mobile artifacts to `static/downloads/` and generates a single release manifest consumed by the website and backend APIs.

## 1) Preconditions

- Branch: `release/multiprotocol-live-only`
- Backend + website deployed on Hetzner hosts only
- No secrets in repository or release artifacts
- Linux build host has:
  - Flutter SDK
  - `wg-quick`
  - `dpkg-deb`

## 2) Core Release Command

```bash
./scripts/build_release_all.sh
```

Optional overrides:

```bash
SECUREWAVE_RELEASE_INPUT_DIR=/path/to/native-artifacts \
SECUREWAVE_BUILD_ANDROID=1 \
./scripts/build_release_all.sh 4.0.0+1
```

## 3) Output Layout

- Canonical release files:
  - `artifacts/releases/<version>/version.json`
  - `artifacts/releases/<version>/checksums.txt`
- Published website/backend files:
  - `static/downloads/version.json`
  - `static/downloads/checksums-<version-tag>.txt`
  - `static/downloads/<artifact files>`

The script removes stale top-level files in `static/downloads/` and republishes only the latest manifest-backed artifacts.

## 4) Platform Notes

### Linux (Primary)

- Primary distribution: `.deb`
- Built automatically by `securewave_app/scripts/build_deb.sh`
- Dependency story: package depends on `wireguard-tools` and `policykit-1`

### Windows

- Build on a native Windows host using:
  - `windows_installer/build_windows_installer.ps1`
- Drop artifact at:
  - `${SECUREWAVE_RELEASE_INPUT_DIR}/securewave-windows-x64-setup.exe`
- Production requirement:
  - Authenticode signing before publication

### macOS

- Build/sign on a native macOS host
- Drop artifact at:
  - `${SECUREWAVE_RELEASE_INPUT_DIR}/securewave-macos-universal.dmg` or
  - `${SECUREWAVE_RELEASE_INPUT_DIR}/securewave-macos-arm64.dmg`
- If signing/notarization is missing, keep manifest entry as Preview/Unavailable

### Android

- Optional local build: `SECUREWAVE_BUILD_ANDROID=1`
- Expected outputs:
  - APK: `securewave_app/build/app/outputs/flutter-apk/app-release.apk`
  - AAB: `securewave_app/build/app/outputs/bundle/release/app-release.aab`
- Or ingest from `${SECUREWAVE_RELEASE_INPUT_DIR}`

### iOS

- Website does not serve a direct `.ipa`
- Distribution channel is TestFlight/App Store only
- Manual signing/provisioning remains required per Apple tooling

## 5) Website + API Behavior

- Website download buttons and platform recommendation are API-driven (`/api/downloads` and `/api/downloads/detect`)
- Backend reads `static/downloads/version.json` as the only download source of truth
- If an artifact is declared available but file is missing, API downgrades it to unavailable

## 6) Verification Checklist

```bash
pytest tests/unit/test_download_manifest.py
./scripts/ci_multiprotocol_safety_check.sh
./scripts/verify_website.sh
```

Optional API smoke (with backend running locally):

```bash
curl -fsS http://127.0.0.1:8000/api/downloads | jq '.version, .downloads | length'
curl -fsS http://127.0.0.1:8000/api/downloads/detect -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64)'
```

## 7) Live Mode Environment Variables

Set these in runtime/deployment secrets (not in repo):

- `ENVIRONMENT=production`
- `APP_VERSION=<release-version>`
- `ACCESS_TOKEN_SECRET=<secure-random>`
- `REFRESH_TOKEN_SECRET=<secure-random>`
- `AUTH_ENCRYPTION_KEY=<fernet-key>`
- `WG_ENCRYPTION_KEY=<fernet-key>`
- `DATABASE_URL=<production-db-url>`
- `CORS_ORIGINS=<https origins>`

Optional release path override:

- `SECUREWAVE_RELEASE_MANIFEST_PATH=/absolute/path/to/version.json`

