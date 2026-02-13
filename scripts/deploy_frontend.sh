#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/securewave_app"
OUTPUT_DIR="$ROOT_DIR/artifacts/frontend-builds"
mkdir -p "$OUTPUT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v flutter >/dev/null 2>&1 || fail "flutter not found in PATH"

cd "$APP_DIR"
flutter --version
flutter pub get

echo "Running flutter analyze..."
flutter analyze

echo "Running flutter test..."
flutter test

echo "Running flutter integration harness..."
flutter test integration_test

echo "Building Android APK..."
flutter build apk --release --dart-define=SECUREWAVE_USE_MOCK_API=false

if [[ "$(uname -s)" == "Linux" ]]; then
  echo "Building Linux desktop..."
  flutter config --enable-linux-desktop >/dev/null
  flutter build linux --release --dart-define=SECUREWAVE_USE_MOCK_API=false
else
  echo "Skipping Linux desktop build (not running on Linux host)."
fi

if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
  echo "Building Windows desktop..."
  flutter config --enable-windows-desktop >/dev/null
  flutter build windows --release --dart-define=SECUREWAVE_USE_MOCK_API=false
else
  echo "Skipping Windows desktop build (run this script on Windows CI/host for windows binaries)."
fi

echo "Frontend deploy checks complete."
