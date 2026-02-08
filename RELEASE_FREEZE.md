# Release Freeze: v1.0.0 (Non-Apple, Azure-Excluded)

This branch/tag freezes a known-good SecureWave state for **Android, Windows, Linux, and Web**.

## Azure Is Intentionally Disabled

The Azure subscription is currently unavailable. For this release freeze:

- All Azure-dependent code paths are expected to be **disabled, mocked, or safely short-circuited**.
- Test runs must not attempt to deploy, provision, or call Azure control-plane APIs.
- Any Azure-only tests must be skipped and annotated with `# AZURE_SKIPPED: <reason>`.

## Validated Platforms

- Android: validated via Flutter analysis/tests (no device-dependent e2e in this freeze)
- Windows: validated via build-time and logic-level checks (no Azure/WireGuard server reachability required)
- Linux: validated via backend/unit tests and local backend simulation
- Web: validated via local backend + static site simulation (no cloud URLs)

Apple platforms (iOS/macOS) are intentionally excluded from this freeze.

## How To Rerun The Non-Azure Test Suite

Backend (Python):

```bash
python3 -m compileall services/ ml/ -q
.venv/bin/pytest -q
```

Flutter app (Dart):

```bash
cd securewave_app
flutter analyze
flutter test
```

End-to-end local simulation (backend via uvicorn + sqlite, no cloud URLs):

```bash
bash sandbox/e2e_simulation/run_non_azure_suite.sh
```

