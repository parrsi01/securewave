#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_DIR}"

flutter config --enable-linux-desktop >/dev/null

MOCK_VPN="${SECUREWAVE_MOCK_VPN:-true}"

mapfile -t targets < <(find integration_test -maxdepth 1 -type f -name '*_test.dart' | sort)

if [ "$#" -gt 0 ]; then
  targets=("$@")
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo "No integration tests found under integration_test/"
  exit 0
fi

flutter devices

for target in "${targets[@]}"; do
  echo "Running Linux integration test: ${target}"
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a flutter test "${target}" \
      --dart-define=SECUREWAVE_MOCK_VPN="${MOCK_VPN}"
  else
    flutter test "${target}" \
      --dart-define=SECUREWAVE_MOCK_VPN="${MOCK_VPN}"
  fi
done
