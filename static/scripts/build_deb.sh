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

version="$(cat "$ROOT_DIR/../VERSION" 2>/dev/null | tr -d '\r' | xargs)"
if [[ -z "$version" ]]; then
  version="$(awk '/^version:/ {print $2}' pubspec.yaml)"
fi
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
Depends: wireguard-tools, policykit-1
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

# postinst: install a scoped WireGuard helper + polkit rule so SecureWave
# reconnect/reset operations do not require repetitive password prompts.
cat <<'POSTINST' > "$staging_dir/DEBIAN/postinst"
#!/bin/bash
set -e
HELPER_DIR=/usr/local/libexec
HELPER=$HELPER_DIR/securewave-wg-quick
install -d -m 0755 "$HELPER_DIR"
cat > "$HELPER" <<'HELPER_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: securewave-wg-quick <up|down> <config-path>" >&2
  exit 64
fi

action="$1"
config="$2"
case "$action" in
  up|down) ;;
  *)
    echo "securewave-wg-quick: invalid action '$action'" >&2
    exit 64
    ;;
esac

case "$config" in
  /home/*/.config/securewave/*.conf|/root/.config/securewave/*.conf) ;;
  *)
    echo "securewave-wg-quick: refusing unsafe config path '$config'" >&2
    exit 64
    ;;
esac

if [[ "$action" == "up" ]]; then
  STATE_DIR=/run/securewave
  POLICY_FILE=$STATE_DIR/sw-wg.output-policy
  ENDPOINT_FILE=$STATE_DIR/sw-wg.endpoint-ips
  if [[ -f "$ENDPOINT_FILE" ]]; then
    while IFS= read -r ip; do
      [[ -n "$ip" ]] || continue
      iptables -D OUTPUT -d "$ip" -j ACCEPT >/dev/null 2>&1 || true
      ip route del "$ip/32" >/dev/null 2>&1 || true
    done < "$ENDPOINT_FILE"
  fi
  iptables -D OUTPUT -o sw-wg -j ACCEPT >/dev/null 2>&1 || true
  if [[ -f "$POLICY_FILE" ]]; then
    prev_policy="$(tr -d '[:space:]' < "$POLICY_FILE")"
    [[ -n "$prev_policy" ]] || prev_policy=ACCEPT
    iptables -P OUTPUT "$prev_policy" >/dev/null 2>&1 || true
  else
    iptables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
  fi
  rm -f "$POLICY_FILE" "$ENDPOINT_FILE"
  wg-quick down "$config" >/dev/null 2>&1 || true
  ip link delete sw-wg >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8; do
    ip rule del table 51820 >/dev/null 2>&1 || break
  done
fi

exec wg-quick "$action" "$config"
HELPER_SCRIPT
chmod 0755 "$HELPER"

POLKIT_RULES_DIR=/etc/polkit-1/rules.d
POLKIT_RULE=$POLKIT_RULES_DIR/50-securewave-wg.rules
mkdir -p "$POLKIT_RULES_DIR"
cat > "$POLKIT_RULE" <<'RULE'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "/usr/local/libexec/securewave-wg-quick" &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
RULE
chmod 0644 "$POLKIT_RULE"
POSTINST
chmod 0755 "$staging_dir/DEBIAN/postinst"

# postrm: remove the polkit rule on uninstall
cat <<'POSTRM' > "$staging_dir/DEBIAN/postrm"
#!/bin/bash
set -e
rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules
rm -f /usr/local/libexec/securewave-wg-quick
POSTRM
chmod 0755 "$staging_dir/DEBIAN/postrm"

mkdir -p "$output_dir"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

dpkg-deb --build "$staging_dir" "$output_file" >/dev/null

echo "OK: Built $output_file"
