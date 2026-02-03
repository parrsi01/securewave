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
  "$staging_dir/usr/share/icons/hicolor/256x256/apps"

cp -a "$bundle_dir/"* "$staging_dir/usr/lib/securewave/"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
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

mkdir -p "$output_dir"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

dpkg-deb --build "$staging_dir" "$output_file" >/dev/null

echo "OK: Built $output_file"
