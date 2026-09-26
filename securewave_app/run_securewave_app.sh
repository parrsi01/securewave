#!/usr/bin/env bash
set -euo pipefail

cd /home/sp/cyber-course/projects/securewave/securewave_app

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not installed. Run 'flutter doctor' after installing Flutter." >&2
  exit 1
fi

flutter pub get

flutter run -d linux
