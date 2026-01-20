#!/usr/bin/env bash
set -euo pipefail

cd /home/sp/cyber-course/projects/securewave/securewave_app

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not installed. Run 'flutter doctor' after installing Flutter." >&2
  exit 1
fi

# Create platform folders (only needed once)
if [ ! -d "android" ] && [ ! -d "ios" ] && [ ! -d "macos" ] && [ ! -d "windows" ] && [ ! -d "linux" ]; then
  flutter create .
fi

flutter pub get
flutter pub run flutter_launcher_icons

# Default to linux for this VM
TARGET=${1:-linux}
flutter run -d "$TARGET"
