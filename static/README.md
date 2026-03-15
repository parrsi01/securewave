# SecureWave App

SecureWave is a Flutter control-plane app that integrates with the SecureWave API
and provisions ephemeral WireGuard tunnel profiles for native VPN tunnel providers.

**No config files ever:** users never download or manage `.conf` files. The app fetches
profiles from the backend after login, stores them in secure storage, and connects via
native implementations.

## What Works Without Xcode

- Full Flutter UI + routing
- Auth + session persistence
- Server list, device management, VPN allocation
- Config fetch from API and handoff to native bridge

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
   - `flutter run -d linux`
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
