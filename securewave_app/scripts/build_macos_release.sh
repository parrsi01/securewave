#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

entitlements_file="$ROOT_DIR/macos/Runner/Release.entitlements"

# Guard against shipping a macOS build without Network Extension entitlements.
if [[ ! -f "$entitlements_file" ]]; then
  echo "NO-GO: macOS Release.entitlements missing. VPN is not configured for macOS." >&2
  echo "See securewave_app/MACOS_VPN_SETUP.md for required entitlements and signing." >&2
  exit 1
fi

if ! grep -q "com.apple.developer.networking.networkextension" "$entitlements_file"; then
  echo "NO-GO: macOS Network Extension entitlement is not present." >&2
  echo "Add Network Extension entitlements and signing before packaging. See securewave_app/MACOS_VPN_SETUP.md." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not installed or not on PATH." >&2
  exit 1
fi

flutter pub get
flutter build macos --release
