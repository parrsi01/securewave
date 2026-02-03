#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not installed or not on PATH."
  exit 1
fi

if ! command -v appimage-builder >/dev/null 2>&1; then
  echo "ERROR: appimage-builder is not installed."
  echo "Install: pip install --user appimage-builder"
  exit 1
fi

flutter pub get
flutter build linux --release

cp -f assets/icon.png packaging/appimage/securewave.png

appimage-builder --recipe packaging/appimage/appimage-builder.yml --skip-test
