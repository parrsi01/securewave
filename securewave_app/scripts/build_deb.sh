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
  "$staging_dir/usr/lib/tmpfiles.d" \
  "$staging_dir/usr/share/applications" \
  "$staging_dir/usr/share/icons/hicolor/256x256/apps" \
  "$staging_dir/usr/share/securewave/packaging/linux"

cp -a "$bundle_dir/"* "$staging_dir/usr/lib/securewave/"
helperd_source="$bundle_dir/packaging/linux/securewave-helperd"
if [[ ! -x "$helperd_source" ]]; then
  echo "ERROR: securewave-helperd was not produced in the Linux bundle." >&2
  exit 1
fi
cp -f "$ROOT_DIR/packaging/linux/securewave-wg-quick" "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick"
cp -f "$helperd_source" "$staging_dir/usr/share/securewave/packaging/linux/securewave-helperd"
cp -f "$ROOT_DIR/packaging/linux/securewave-helper.service" "$staging_dir/usr/share/securewave/packaging/linux/securewave-helper.service"
cp -f "$ROOT_DIR/packaging/linux/securewave-helper.tmpfiles" "$staging_dir/usr/share/securewave/packaging/linux/securewave-helper.tmpfiles"
cp -f "$ROOT_DIR/packaging/linux/securewave-helper.tmpfiles" "$staging_dir/usr/lib/tmpfiles.d/securewave-helper.conf"
cp -f "$ROOT_DIR/packaging/linux/securewave-wg-quick.contract" "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick.contract"
chmod 0755 "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick" \
  "$staging_dir/usr/share/securewave/packaging/linux/securewave-helperd"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: wireguard-tools, openvpn, network-manager, network-manager-strongswan, strongswan, strongswan-swanctl, strongswan-charon, libcharon-extra-plugins, libstrongswan-extra-plugins, iproute2, iptables, acl, systemd
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
HELPERD=$HELPER_DIR/securewave-helperd
HELPER_CONTRACT=$HELPER_DIR/securewave-wg-quick.contract
SOURCE_DIR=/usr/share/securewave/packaging/linux
SOURCE_HELPER=$SOURCE_DIR/securewave-wg-quick
SOURCE_HELPERD=$SOURCE_DIR/securewave-helperd
SOURCE_CONTRACT=$SOURCE_DIR/securewave-wg-quick.contract
SOURCE_SERVICE=$SOURCE_DIR/securewave-helper.service
SOURCE_TMPFILES=$SOURCE_DIR/securewave-helper.tmpfiles
SERVICE_FILE=/etc/systemd/system/securewave-helper.service
TMPFILES_FILE=/usr/lib/tmpfiles.d/securewave-helper.conf
RUNTIME_GROUP=securewave
RUNTIME_DIR=/run/securewave
AUTH_DIR=/etc/securewave
AUTH_FILE=$AUTH_DIR/helper-users
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER" "$HELPER"
install -m 0755 "$SOURCE_HELPERD" "$HELPERD"
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"

if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
  groupadd --system "$RUNTIME_GROUP"
fi

install -d -o root -g root -m 0755 "$AUTH_DIR"
: > "$AUTH_FILE"
chmod 0644 "$AUTH_FILE"
add_allowed_user() {
  local user="$1"
  local uid
  [[ -n "$user" && "$user" != "root" ]] || return 0
  id "$user" >/dev/null 2>&1 || return 0
  uid="$(id -u "$user")"
  grep -qx "$uid" "$AUTH_FILE" 2>/dev/null || printf '%s\n' "$uid" >> "$AUTH_FILE"
  usermod -a -G "$RUNTIME_GROUP" "$user" || true
}
ALLOW_USER="${SUDO_USER:-}"
if [[ -z "$ALLOW_USER" ]]; then
  ALLOW_USER="$(logname 2>/dev/null || true)"
fi
add_allowed_user "$ALLOW_USER"

install -d -o root -g "$RUNTIME_GROUP" -m 0750 "$RUNTIME_DIR"
rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules
install -m 0644 "$SOURCE_SERVICE" "$SERVICE_FILE"
install -m 0644 "$SOURCE_TMPFILES" "$TMPFILES_FILE"
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  command -v systemd-tmpfiles >/dev/null 2>&1 && systemd-tmpfiles --create "$TMPFILES_FILE" || true
  systemctl daemon-reload
  systemctl enable --now securewave-helper.service
  systemctl restart securewave-helper.service
else
  echo "SecureWave helper service requires systemd; install completed but service was not started." >&2
fi
POSTINST

cat <<'PRERM' > "$staging_dir/DEBIAN/prerm"
#!/bin/bash
set -e
HELPER=/usr/local/libexec/securewave-wg-quick
if [[ -x "$HELPER" ]]; then
  "$HELPER" policy-clear-link sw-wg >/dev/null 2>&1 || true
  "$HELPER" ikev2-down >/dev/null 2>&1 || true
  "$HELPER" ikev2-delete >/dev/null 2>&1 || true
fi
for proc_dir in /proc/[0-9]*; do
  [[ -r "$proc_dir/comm" && -r "$proc_dir/cmdline" ]] || continue
  [[ "$(cat "$proc_dir/comm" 2>/dev/null)" == "openvpn" ]] || continue
  [[ "$(stat -c %u "$proc_dir" 2>/dev/null)" == "0" ]] || continue
  if tr '\0' '\n' < "$proc_dir/cmdline" | grep -Eq '/(\.config/securewave|run/securewave)/securewave\.ovpn$'; then
    kill -TERM "${proc_dir##*/}" >/dev/null 2>&1 || true
  fi
done
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl stop securewave-helper.service >/dev/null 2>&1 || true
  systemctl disable securewave-helper.service >/dev/null 2>&1 || true
fi
PRERM

cat <<'POSTRM' > "$staging_dir/DEBIAN/postrm"
#!/bin/bash
set -e
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl disable --now securewave-helper.service >/dev/null 2>&1 || true
fi
rm -f /etc/systemd/system/securewave-helper.service
rm -f /usr/lib/tmpfiles.d/securewave-helper.conf
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
rm -f /run/securewave/helper.sock
rm -f /run/securewave/sw-wg.output-policy /run/securewave/sw-wg.endpoint-ips
rmdir /run/securewave >/dev/null 2>&1 || true
rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules
rm -f /usr/local/libexec/securewave-wg-quick.contract
rm -f /usr/local/libexec/securewave-helperd
rm -f /usr/local/libexec/securewave-wg-quick
rm -f /etc/securewave/helper-users
rmdir /etc/securewave >/dev/null 2>&1 || true
if [[ "${1:-}" == "purge" ]] && getent group securewave >/dev/null 2>&1; then
  groupdel securewave >/dev/null 2>&1 || true
fi
POSTRM
chmod 0755 "$staging_dir/DEBIAN/postinst" "$staging_dir/DEBIAN/prerm" "$staging_dir/DEBIAN/postrm"

mkdir -p "$output_dir"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

dpkg-deb --root-owner-group --build "$staging_dir" "$output_file" >/dev/null

echo "OK: Built $output_file"
echo "OK: Local package only; no release artifact was published."
