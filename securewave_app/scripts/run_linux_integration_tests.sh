#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

resolve_flutter_bin() {
  if [[ -n "${FLUTTER_BIN:-}" && -x "${FLUTTER_BIN}" ]]; then
    printf '%s\n' "${FLUTTER_BIN}"
    return 0
  fi
  for candidate in \
    "${HOME}/flutter/bin/flutter" \
    "/opt/flutter/bin/flutter" \
    "/snap/bin/flutter" \
    "/usr/local/bin/flutter"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

cd "${APP_DIR}"

FLUTTER="$(resolve_flutter_bin)" || {
  echo "Flutter SDK not found. Set FLUTTER_BIN to an absolute flutter path." >&2
  exit 1
}

"${FLUTTER}" pub get
"${FLUTTER}" config --enable-linux-desktop >/dev/null

MOCK_VPN="${SECUREWAVE_MOCK_VPN:-true}"

mapfile -t targets < <(find integration_test -maxdepth 1 -type f -name '*_test.dart' | sort)

if [ "$#" -gt 0 ]; then
  targets=("$@")
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo "No integration tests found under integration_test/"
  exit 0
fi

"${FLUTTER}" devices

for target in "${targets[@]}"; do
  echo "Running Linux integration test: ${target}"
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a "${FLUTTER}" test "${target}" \
      --dart-define=SECUREWAVE_MOCK_VPN="${MOCK_VPN}"
  else
    "${FLUTTER}" test "${target}" \
      --dart-define=SECUREWAVE_MOCK_VPN="${MOCK_VPN}"
  fi
done
