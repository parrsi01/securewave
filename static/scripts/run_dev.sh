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

# Kill any existing Flutter-built securewave_app binary (not this script)
if pgrep -f "bundle/securewave_app$" > /dev/null 2>&1; then
  echo "Stopping existing instance..."
  pkill -f "bundle/securewave_app$" || true
  sleep 1
fi

# Ensure dependencies
flutter pub get

OS="$(uname -s)"
case "$OS" in
  Linux*)
    echo "Platform: Linux"
    echo "Installing Linux build deps (if missing)..."
    if ! dpkg -s libgtk-3-dev &>/dev/null; then
      echo "Run: sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev"
      echo "(skipping auto-install; rerun after installing)"
    fi
    flutter run -d linux
    ;;
  Darwin*)
    echo "Platform: macOS"
    echo ""
    echo "  iOS:   flutter run -d <device-id>"
    echo "         (Requires Runner.xcworkspace, not .xcodeproj)"
    echo "  macOS: flutter run -d macos"
    echo ""
    echo "Launching macOS desktop build..."
    flutter run -d macos
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "Platform: Windows"
    flutter run -d windows
    ;;
  *)
    echo "Unknown platform: $OS"
    echo "Try: flutter run -d <platform>"
    exit 1
    ;;
esac
