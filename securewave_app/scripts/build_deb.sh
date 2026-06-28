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
  echo "ERROR: flutter is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "ERROR: dpkg-deb is required. Install with: sudo apt-get install dpkg" >&2
  exit 1
fi

flutter pub get
flutter build linux --release

bundle_dir=""
for candidate in build/linux/*/release/bundle; do
  if [[ -d "$candidate" ]]; then
    bundle_dir="$candidate"
    break
  fi
done

if [[ -z "$bundle_dir" ]]; then
  echo "ERROR: Flutter Linux bundle not found under build/linux/*/release/bundle." >&2
  exit 1
fi

version="$(awk '/^version:/ {print $2}' pubspec.yaml)"
if [[ -z "$version" ]]; then
  echo "ERROR: Unable to read version from pubspec.yaml." >&2
  exit 1
fi

arch="$(dpkg --print-architecture)"
package_name="securewave-vpn"

staging_dir="$ROOT_DIR/build/packaging/deb"
output_dir="$ROOT_DIR/build/packaging"

rm -rf "$staging_dir"
mkdir -p "$staging_dir/DEBIAN" \
  "$staging_dir/usr/lib/securewave" \
  "$staging_dir/usr/bin" \
  "$staging_dir/usr/share/applications" \
  "$staging_dir/usr/share/icons/hicolor/256x256/apps" \
  "$staging_dir/usr/share/securewave/packaging/linux"

cp -a "$bundle_dir/"* "$staging_dir/usr/lib/securewave/"
cp -f "$ROOT_DIR/packaging/linux/securewave-wg-quick" "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick"
cp -f "$ROOT_DIR/packaging/linux/50-securewave-wg.rules" "$staging_dir/usr/share/securewave/packaging/linux/50-securewave-wg.rules"
cp -f "$ROOT_DIR/packaging/linux/securewave-wg-quick.contract" "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick.contract"
chmod 0755 "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: wireguard-tools, openvpn, network-manager, network-manager-strongswan, strongswan, policykit-1
Maintainer: SecureWave Release <release@securewave.app>
Description: SecureWave VPN desktop client
CONTROL

cat <<'DESKTOP' > "$staging_dir/usr/share/applications/securewave-vpn.desktop"
[Desktop Entry]
Name=SecureWave VPN
Exec=securewave-vpn
Type=Application
Categories=Network;Security;
Icon=securewave-vpn
Terminal=false
DESKTOP

if [[ -f "$ROOT_DIR/assets/icon.png" ]]; then
  cp -f "$ROOT_DIR/assets/icon.png" "$staging_dir/usr/share/icons/hicolor/256x256/apps/securewave-vpn.png"
fi

cat <<'WRAPPER' > "$staging_dir/usr/bin/securewave-vpn"
#!/usr/bin/env bash
set -euo pipefail
exec /usr/lib/securewave/securewave_app "$@"
WRAPPER
chmod 0755 "$staging_dir/usr/bin/securewave-vpn"

cat <<'POSTINST' > "$staging_dir/DEBIAN/postinst"
#!/bin/bash
set -e
HELPER_DIR=/usr/local/libexec
HELPER=$HELPER_DIR/securewave-wg-quick
HELPER_CONTRACT=$HELPER_DIR/securewave-wg-quick.contract
SOURCE_DIR=/usr/share/securewave/packaging/linux
SOURCE_HELPER=$SOURCE_DIR/securewave-wg-quick
SOURCE_CONTRACT=$SOURCE_DIR/securewave-wg-quick.contract
SOURCE_POLKIT_RULE=$SOURCE_DIR/50-securewave-wg.rules
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER" "$HELPER"

render_polkit_rule() {
  local allow_user="${1:-}"
  if [[ -z "$allow_user" || "$allow_user" == "root" ]]; then
    install -m 0644 "$SOURCE_POLKIT_RULE" "$POLKIT_RULE"
    return 0
  fi

  local escaped_user="$allow_user"
  escaped_user="${escaped_user//\\/\\\\}"
  escaped_user="${escaped_user//&/\\&}"
  escaped_user="${escaped_user//\//\\/}"

  sed "s/__SECUREWAVE_ALLOWED_USER__/${escaped_user}/g" \
    "$SOURCE_POLKIT_RULE" > "$POLKIT_RULE"
  chmod 0644 "$POLKIT_RULE"
}

reload_polkit() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl try-reload-or-restart polkit.service >/dev/null 2>&1 || true
  fi
}

POLKIT_RULES_DIR=/etc/polkit-1/rules.d
POLKIT_RULE=$POLKIT_RULES_DIR/50-securewave-wg.rules
mkdir -p "$POLKIT_RULES_DIR"
ALLOW_USER="${SUDO_USER:-}"
if [[ -z "$ALLOW_USER" ]]; then
  ALLOW_USER="$(logname 2>/dev/null || true)"
fi
render_polkit_rule "$ALLOW_USER"
reload_polkit
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"
POSTINST

cat <<'POSTRM' > "$staging_dir/DEBIAN/postrm"
#!/bin/bash
set -e
rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules
rm -f /usr/local/libexec/securewave-wg-quick.contract
rm -f /usr/local/libexec/securewave-wg-quick
POSTRM
chmod 0755 "$staging_dir/DEBIAN/postinst" "$staging_dir/DEBIAN/postrm"

mkdir -p "$output_dir"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

dpkg-deb --build "$staging_dir" "$output_file" >/dev/null

echo "OK: Built $output_file"
