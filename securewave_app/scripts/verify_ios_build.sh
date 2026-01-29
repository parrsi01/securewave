#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/ios"

if [[ ! -f "${IOS_DIR}/Flutter/Generated.xcconfig" ]]; then
  echo "error: Missing ios/Flutter/Generated.xcconfig. Run 'flutter pub get' and rebuild."
  exit 1
fi

if [[ ! -d "${IOS_DIR}/Pods" ]]; then
  echo "error: Missing ios/Pods. Run 'pod install' from ios/."
  exit 1
fi

if [[ "${PROJECT_FILE_PATH:-}" == *"Runner.xcodeproj"* ]] && [[ -z "${WORKSPACE_PATH:-}" ]]; then
  echo "error: Xcode project opened directly. Use Runner.xcworkspace."
  exit 1
fi

echo "iOS build validation passed."
