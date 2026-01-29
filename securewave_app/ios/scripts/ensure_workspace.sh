#!/bin/bash
set -euo pipefail

if [[ -z "${WORKSPACE_PATH:-}" ]]; then
  echo "error: Open Runner.xcworkspace (not Runner.xcodeproj) before building."
  exit 1
fi

if [[ "${WORKSPACE_PATH}" != *"Runner.xcworkspace"* ]]; then
  echo "error: Expected Runner.xcworkspace but got ${WORKSPACE_PATH}."
  exit 1
fi
