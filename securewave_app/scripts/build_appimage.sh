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

flutter pub get
flutter build linux --release

for bundle in build/linux/*/release/bundle; do
  [[ -d "$bundle" ]] || continue
  rm -rf "$bundle/packaging/linux" "$bundle/scripts/install_linux_helper.sh"
  cat > "$bundle/README-LINUX-VPN.txt" <<'EOF'
SecureWave AppImage

This AppImage can launch the SecureWave UI. Full-device VPN routing requires
the root-owned SecureWave helper service. Install the SecureWave .deb package
for full no-prompt VPN connect/disconnect.
EOF
done

cp -f assets/icon.png packaging/appimage/securewave.png

appimage-builder --recipe packaging/appimage/appimage-builder.yml --skip-test
