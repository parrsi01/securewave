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

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required to record package provenance." >&2
  exit 1
fi

source_commit="$(git rev-parse --verify HEAD 2>/dev/null || true)"
if [[ -z "$source_commit" ]]; then
  echo "ERROR: unable to determine the source commit for package provenance." >&2
  exit 1
fi

source_tree_state="$(git status --porcelain --untracked-files=all)"
if [[ -n "$source_tree_state" ]]; then
  echo "ERROR: refusing to package a dirty source tree." >&2
  echo "Commit or remove all tracked and untracked changes before building." >&2
  exit 1
fi

package_profile="${SECUREWAVE_PACKAGE_PROFILE:-production}"
api_base="${SECUREWAVE_API_BASE_URL:-}"
if [[ "$package_profile" != "production" && "$package_profile" != "codex-local" ]]; then
  echo "ERROR: unsupported package profile." >&2
  exit 1
fi
if [[ -z "$api_base" ]]; then
  echo "ERROR: SECUREWAVE_API_BASE_URL must be supplied explicitly." >&2
  exit 1
fi
case "$package_profile" in
  production)
    if [[ "${SECUREWAVE_CODEX_LOCAL:-false}" == "true" ]]; then
      echo "ERROR: production packaging rejects the Codex-local flag." >&2
      exit 1
    fi
    if [[ ! "$api_base" =~ ^https://[^/[:space:]]+/api/?$ ]]; then
      echo "ERROR: production packaging requires an explicit HTTPS /api base." >&2
      exit 1
    fi
    if [[ "$api_base" == *"@"* || "$api_base" == *"?"* || "$api_base" == *"#"* ]]; then
      echo "ERROR: production packaging rejects API credentials, queries, and fragments." >&2
      exit 1
    fi
    case "$api_base" in
      https://localhost/*|https://127.*/*|https://0.0.0.0/*)
        echo "ERROR: production packaging rejects a loopback API base." >&2
        exit 1
        ;;
    esac
    if [[ "$api_base" == "https://[::1]/api" || "$api_base" == "https://[::1]/api/" ]]; then
      echo "ERROR: production packaging rejects a loopback API base." >&2
      exit 1
    fi
    codex_local_define="false"
    package_name="securewave-vpn"
    ;;
  codex-local)
    if [[ "${SECUREWAVE_CODEX_LOCAL:-false}" != "true" ]]; then
      echo "ERROR: Codex-local packaging requires SECUREWAVE_CODEX_LOCAL=true." >&2
      exit 1
    fi
    if [[ ! "$api_base" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]+)?/api/?$ ]]; then
      echo "ERROR: Codex-local packaging requires an HTTP loopback /api base." >&2
      exit 1
    fi
    codex_local_define="true"
    package_name="securewave-vpn-codex-local"
    ;;
esac

flutter pub get
flutter build linux --release \
  --dart-define=SECUREWAVE_API_BASE_URL="$api_base" \
  --dart-define=SECUREWAVE_CODEX_LOCAL="$codex_local_define" \
  --dart-define=SECUREWAVE_USE_MOCK_API=false

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

staging_dir="$ROOT_DIR/build/packaging/deb"
output_dir="${SECUREWAVE_PACKAGE_OUTPUT_DIR:-$ROOT_DIR/build/packaging}"

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

release_dir="$staging_dir/usr/share/securewave/release"
mkdir -p "$release_dir"
printf '%s\n' "$source_commit" > "$release_dir/source-sha"
printf '%s\n' "clean" > "$release_dir/source-tree-state"
printf '%s\n' "$version" > "$release_dir/app-version"
printf '%s\n' "$arch" > "$release_dir/package-architecture"
printf '%s\n' "$package_profile" > "$release_dir/package-profile"
printf '%s\n' "$(printf '%s' "$api_base" | sha256sum | awk '{print $1}')" > "$release_dir/api-base-fingerprint"
tr -d '[:space:]' < "$ROOT_DIR/packaging/linux/securewave-wg-quick.contract" > "$release_dir/helper-contract"
printf '\n' >> "$release_dir/helper-contract"
chmod 0644 "$release_dir/source-sha" "$release_dir/source-tree-state" \
  "$release_dir/app-version" "$release_dir/package-architecture" \
  "$release_dir/package-profile" "$release_dir/api-base-fingerprint" \
  "$release_dir/helper-contract"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: wireguard-tools, openvpn, network-manager, libgtk-3-0, libsecret-1-0, libegl1, iproute2, iptables, acl, systemd
Suggests: network-manager-strongswan, strongswan, strongswan-swanctl, strongswan-charon, libcharon-extra-plugins, libstrongswan-extra-plugins
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

# Keep the native Flutter secure-storage linkage and Debian runtime contract
# synchronized. A package that contains libsecret-linked code but omits the
# runtime dependency can launch on one workstation and fail at keyring access
# on another, which is a login regression rather than a database failure.
package_depends="$(dpkg-deb --field "$output_file" Depends 2>/dev/null || true)"
if ! printf '%s\n' "$package_depends" \
  | tr ',' '\n' \
  | sed 's/^ *//; s/ *$//' \
  | grep -Fx 'libsecret-1-0' >/dev/null; then
  echo "ERROR: built package is missing required libsecret-1-0 runtime dependency." >&2
  exit 1
fi

echo "OK: Built $output_file"
if [[ "$package_profile" == "codex-local" ]]; then
  echo "OK: Codex-local package only; no release artifact was published."
else
  echo "OK: Production-profile package built locally; no release artifact was published."
fi
