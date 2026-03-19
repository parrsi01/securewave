#!/usr/bin/env bash
# SecureWave Flutter - local development runner
# Detects the current OS and launches the Flutter app for that platform.
# Kills any existing instance first so only one is ever running.
# Usage: bash securewave_app/scripts/run_dev.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_DIR"

echo "SecureWave dev runner"
echo "Working directory: $APP_DIR"

# Kill any existing Flutter-built securewave_app binary (not this script).
# Pattern anchored to "bundle/securewave_app" at end of cmdline — only matches
# the built app binary, not this script or any flutter tooling process.
if pgrep -f "bundle/securewave_app$" > /dev/null 2>&1; then
  echo "Stopping existing instance..."
  pkill -f "bundle/securewave_app$" || true
  sleep 1
fi

# Ensure dependencies
flutter pub get

# Default API URL (override with API_BASE_URL env var if needed)
API_URL="${API_BASE_URL:-https://api.securewaveapp.com}"

OS="$(uname -s)"
case "$OS" in
  Linux*)
    echo "Platform: Linux"
    echo "API: $API_URL"
    if ! dpkg -s libgtk-3-dev &>/dev/null; then
      echo "Run: sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev"
      echo "(skipping auto-install; rerun after installing)"
    fi
    # Use softpipe (Mesa software renderer) instead of llvmpipe to avoid
    # slow first-frame rendering that triggers the GTK "not responding" dialog.
    # softpipe is lighter and produces faster first frames on headless/VM setups.
    GALLIUM_DRIVER=softpipe flutter run -d linux \
      --dart-define=API_BASE_URL="$API_URL"
    ;;
  Darwin*)
    echo "Platform: macOS"
    echo "API: $API_URL"
    echo ""
    echo "  iOS:   flutter run -d <device-id>"
    echo "         (Requires Runner.xcworkspace, not .xcodeproj)"
    echo "  macOS: flutter run -d macos"
    echo ""
    echo "Launching macOS desktop build..."
    flutter run -d macos \
      --dart-define=API_BASE_URL="$API_URL"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "Platform: Windows"
    echo "API: $API_URL"
    flutter run -d windows \
      --dart-define=API_BASE_URL="$API_URL"
    ;;
  *)
    echo "Unknown platform: $OS"
    echo "Try: flutter run -d <platform>"
    exit 1
    ;;
esac
