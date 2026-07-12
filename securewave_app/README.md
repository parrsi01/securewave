# SecureWave App

SecureWave is a Flutter control-plane app that integrates with the SecureWave API
and provisions ephemeral VPN profiles for native Linux tunnel providers.

Users should not manually download or manage VPN profiles. The app fetches
profiles from the backend after login, stores the active profile in secure
storage, and hands it to the Linux runner.

The checked-in app has no required local `.env` asset. A clean checkout uses
the live API fallback or explicit `--dart-define` values; an optional local
`.env` may override those values without changing the default live path.

## What Works Without Xcode

- Fresh Flutter UI with Connect, Servers, Account, and Settings tabs
- Auth + session persistence
- Server list, account state, and usage gauge
- WireGuard/OpenVPN profile fetch from API and handoff to native bridge

## What Requires Xcode (iOS/macOS)

- Network Extension target configuration
- Code signing + entitlements
- WireGuardKit package fetch

## Diagnostics

- **Connection diagnostics (small):** Home → "Connection diagnostics" (read-only checks: backend, auth, profile, tunnel).
- **Full diagnostics:** Settings → "Run diagnostics" (includes copyable logs + cache clear).

## Quick Start (Linux/macOS with Flutter)

1. Install Flutter SDK and run `flutter doctor`.
2. From `securewave_app/`:
   - `flutter pub get`
   - `flutter run -d linux --dart-define=SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api`
   - Optional portal overrides use `SECUREWAVE_PORTAL_URL` and `SECUREWAVE_UPGRADE_URL`.
   - Mock API mode is reserved for isolated tests and is never enabled by default.
   - `flutter run -d macos` (UI only; VPN tunneling is unavailable on macOS yet)

## iOS Setup

Follow `IOS_VPN_SETUP.md` to finish the Network Extension configuration in Xcode.
Always open `securewave_app/ios/Runner.xcworkspace` (never `Runner.xcodeproj`).

## Android Setup

Follow `ANDROID_VPN_SETUP.md` to integrate the WireGuard backend.

## Windows Setup

Follow `WINDOWS_VPN_SETUP.md` to integrate the WireGuard backend.

---
© 2026 SecureWave. All rights reserved.
