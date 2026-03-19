#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

flutter pub get

flutter test \
  test/vpn_service_provider_test.dart \
  test/channel_vpn_service_linux_bridge_test.dart \
  --dart-define=SECUREWAVE_MOCK_VPN=false \
  --dart-define=SECUREWAVE_SIM_MODE=false
