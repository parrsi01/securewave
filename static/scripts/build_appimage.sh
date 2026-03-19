#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Guard against packaging when WireGuard tooling is missing on the target platform.
if ! command -v wg-quick >/dev/null 2>&1; then
  echo "ERROR: wg-quick not found. Install WireGuard tools before packaging." >&2
  echo "Install (Debian/Ubuntu): sudo apt-get install -y wireguard-tools" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not installed or not on PATH."
  exit 1
fi

if ! command -v appimage-builder >/dev/null 2>&1; then
  echo "ERROR: appimage-builder is not installed."
  echo "Install: pip install --user appimage-builder"
  exit 1
fi

ensure_release_mock_vpn_disabled() {
  local violations=()
  [[ "${SECUREWAVE_MOCK_VPN:-false}" == "true" ]] && violations+=("SECUREWAVE_MOCK_VPN")
  [[ "${SECUREWAVE_MOCK_VPN_FORCE_FAILURE:-false}" == "true" ]] && violations+=("SECUREWAVE_MOCK_VPN_FORCE_FAILURE")
  [[ "${SECUREWAVE_MOCK_VPN_UNSTABLE:-false}" == "true" ]] && violations+=("SECUREWAVE_MOCK_VPN_UNSTABLE")
  if [[ -n "${SECUREWAVE_MOCK_VPN_LATENCY_MS:-}" && "${SECUREWAVE_MOCK_VPN_LATENCY_MS}" != "300" ]]; then
    violations+=("SECUREWAVE_MOCK_VPN_LATENCY_MS")
  fi
  if [[ "${#violations[@]}" -gt 0 ]]; then
    echo "ERROR: refusing release build with mock VPN settings enabled: ${violations[*]}" >&2
    exit 1
  fi
}

ensure_release_mock_vpn_disabled

flutter pub get
flutter build linux --release



cp -f assets/icon.png packaging/appimage/securewave.png

appimage-builder --recipe packaging/appimage/appimage-builder.yml --skip-test
