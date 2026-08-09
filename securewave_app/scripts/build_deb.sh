#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
cd "$ROOT_DIR"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

for command in flutter wg wg-quick dpkg-deb dpkg sha256sum; do
  require_command "$command"
done

# Keep package metadata reproducible. Flutter bundle contents are copied into
# the staging tree, so normalize every filesystem timestamp before dpkg-deb
# creates the control/data archives. SOURCE_DATE_EPOCH may be supplied by a
# release job; local builds use a stable epoch so the published checksum does
# not change merely because the candidate was committed after the package was
# built.
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 1
fi
export SOURCE_DATE_EPOCH="$source_date_epoch"
export TZ=UTC
export LC_ALL=C

api_url="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
if [[ "$api_url" == *"localhost"* || "$api_url" == *"127.0.0.1"* || "$api_url" == *"<"* ]]; then
  echo "ERROR: refuse to package a local or placeholder API URL: $api_url" >&2
  echo "Set SECUREWAVE_API_BASE_URL to the beta backend URL for a portable package." >&2
  exit 1
fi

flutter pub get
flutter build linux --release \
  --dart-define=SECUREWAVE_API_BASE_URL="$api_url"

# Capture provenance after dependency resolution and compilation so a build
# step that unexpectedly changes tracked source can never be marked clean.
source_commit="unversioned"
source_tree_state="unversioned"
if git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- . ':!securewave_app/build' ':!static/downloads/*.deb')" ]]; then
    source_tree_state="dirty"
  else
    source_tree_state="clean"
  fi
fi

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

version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
[[ -n "$version" ]] || {
  echo "ERROR: unable to read version from pubspec.yaml." >&2
  exit 1
}

arch="$(dpkg --print-architecture)"
package_name="securewave-vpn"
staging_dir="$ROOT_DIR/build/packaging/deb"
output_dir="$ROOT_DIR/build/packaging"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

helperd_source="$bundle_dir/packaging/linux/securewave-helperd"
[[ -x "$helperd_source" ]] || {
  echo "ERROR: securewave-helperd was not produced in the Flutter Linux bundle." >&2
  exit 1
}

rm -rf "$staging_dir"
mkdir -p \
  "$staging_dir/DEBIAN" \
  "$staging_dir/usr/lib/securewave" \
  "$staging_dir/usr/bin" \
  "$staging_dir/usr/lib/tmpfiles.d" \
  "$staging_dir/usr/share/applications" \
  "$staging_dir/usr/share/icons/hicolor/256x256/apps" \
  "$staging_dir/usr/share/securewave/packaging/linux" \
  "$staging_dir/usr/share/securewave/release"

cp -a "$bundle_dir/." "$staging_dir/usr/lib/securewave/"
install -m 0755 "$ROOT_DIR/packaging/linux/securewave-wg-quick" \
  "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick"
install -m 0755 "$helperd_source" \
  "$staging_dir/usr/share/securewave/packaging/linux/securewave-helperd"
install -m 0644 \
  "$ROOT_DIR/packaging/linux/securewave-helper.service" \
  "$ROOT_DIR/packaging/linux/securewave-helper.tmpfiles" \
  "$ROOT_DIR/packaging/linux/securewave-wg-quick.contract" \
  "$staging_dir/usr/share/securewave/packaging/linux/"
install -m 0644 "$ROOT_DIR/packaging/linux/securewave-helper.tmpfiles" \
  "$staging_dir/usr/lib/tmpfiles.d/securewave-helper.conf"

helper_contract="$(tr -d '[:space:]' < "$ROOT_DIR/packaging/linux/securewave-wg-quick.contract")"
[[ "$helper_contract" == "13" ]] || {
  echo "ERROR: Beta 1 requires helper contract 13, got $helper_contract" >&2
  exit 1
}
printf '%s\n' "$version" > "$staging_dir/usr/share/securewave/release/app-version"
printf '%s\n' "$arch" > "$staging_dir/usr/share/securewave/release/package-architecture"
printf '%s\n' "$helper_contract" > "$staging_dir/usr/share/securewave/release/helper-contract"
printf '%s\n' "$source_commit" > "$staging_dir/usr/share/securewave/release/source-sha"
printf '%s\n' "$source_tree_state" > "$staging_dir/usr/share/securewave/release/source-tree-state"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: wireguard-tools, iproute2, iptables, systemd, systemd-resolved, libgtk-3-0t64, libsecret-1-0
Maintainer: SecureWave Release <release@securewave.app>
Description: SecureWave WireGuard Linux beta client
 A small Linux beta client with one authenticated WireGuard runtime.
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
  install -m 0644 "$ROOT_DIR/assets/icon.png" \
    "$staging_dir/usr/share/icons/hicolor/256x256/apps/securewave-vpn.png"
fi

cat <<'WRAPPER' > "$staging_dir/usr/bin/securewave-vpn"
#!/usr/bin/env bash
set -euo pipefail
exec /usr/lib/securewave/securewave_app "$@"
WRAPPER
chmod 0755 "$staging_dir/usr/bin/securewave-vpn"

cat <<'PREINST' > "$staging_dir/DEBIAN/preinst"
#!/bin/sh
set -eu
case "${1:-}" in
  install|upgrade) ;;
  *) exit 0 ;;
esac
PREINST

cat <<'POSTINST' > "$staging_dir/DEBIAN/postinst"
#!/bin/bash
set -euo pipefail

HELPER_DIR=/usr/local/libexec
SOURCE_DIR=/usr/share/securewave/packaging/linux
SERVICE_FILE=/etc/systemd/system/securewave-helper.service
TMPFILES_FILE=/usr/lib/tmpfiles.d/securewave-helper.conf
RUNTIME_GROUP=securewave
RUNTIME_DIR=/run/securewave
AUTH_DIR=/etc/securewave
AUTH_FILE=$AUTH_DIR/helper-users

case "${1:-}" in
  configure) ;;
  abort-upgrade|abort-remove|abort-deconfigure) exit 0 ;;
  *) exit 0 ;;
esac

command -v systemctl >/dev/null 2>&1 || {
  echo "SecureWave requires systemd for its privileged WireGuard helper." >&2
  exit 1
}
[[ -d /run/systemd/system ]] || {
  echo "SecureWave requires a running systemd system service manager." >&2
  exit 1
}

install -d -o root -g root -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_DIR/securewave-wg-quick" \
  "$HELPER_DIR/securewave-wg-quick"
install -m 0755 "$SOURCE_DIR/securewave-helperd" \
  "$HELPER_DIR/securewave-helperd"
install -m 0644 "$SOURCE_DIR/securewave-wg-quick.contract" \
  "$HELPER_DIR/securewave-wg-quick.contract"

if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
  groupadd --system "$RUNTIME_GROUP"
fi

install -d -o root -g root -m 0755 "$AUTH_DIR"
if [[ -e "$AUTH_FILE" || -L "$AUTH_FILE" ]]; then
  [[ -f "$AUTH_FILE" && ! -L "$AUTH_FILE" ]] || {
    echo "Existing SecureWave helper allowlist is not a regular file: $AUTH_FILE" >&2
    exit 1
  }
  [[ "$(stat -c %u "$AUTH_FILE" 2>/dev/null || true)" == "0" ]] || {
    echo "Existing SecureWave helper allowlist is not root-owned: $AUTH_FILE" >&2
    exit 1
  }
else
  install -o root -g root -m 0644 /dev/null "$AUTH_FILE"
fi
chmod 0644 "$AUTH_FILE"

allowed_user="${SECUREWAVE_ALLOWED_USER:-${SUDO_USER:-}}"
if [[ -z "$allowed_user" ]]; then
  allowed_user="$(logname 2>/dev/null || true)"
fi
if [[ -n "$allowed_user" && "$allowed_user" != root ]] && id "$allowed_user" >/dev/null 2>&1; then
  uid="$(id -u "$allowed_user")"
  grep -qx "$uid" "$AUTH_FILE" 2>/dev/null || printf '%s\n' "$uid" >> "$AUTH_FILE"
  usermod -a -G "$RUNTIME_GROUP" "$allowed_user" || true
fi

install -d -o root -g "$RUNTIME_GROUP" -m 0750 "$RUNTIME_DIR"
install -m 0644 "$SOURCE_DIR/securewave-helper.service" "$SERVICE_FILE"
install -m 0644 "$SOURCE_DIR/securewave-helper.tmpfiles" "$TMPFILES_FILE"
systemd-tmpfiles --create "$TMPFILES_FILE"
systemctl daemon-reload
systemctl enable securewave-helper.service
systemctl restart securewave-helper.service
systemctl is-active --quiet securewave-helper.service || {
  echo "SecureWave helper did not start after installation." >&2
  exit 1
}

probe_output=""
for _ in $(seq 1 50); do
  if [[ -S "$RUNTIME_DIR/helper.sock" ]] &&
     probe_output="$(printf 'version=1\nop=probe\n' | "$HELPER_DIR/securewave-helperd" --request 2>/dev/null)" &&
     printf '%s\n' "$probe_output" | grep -qx 'ok=true'; then
    break
  fi
  sleep 0.1
done
printf '%s\n' "$probe_output" | grep -qx 'ok=true' || {
  echo "SecureWave helper failed its post-install contract probe." >&2
  exit 1
}
POSTINST

cat <<'PRERM' > "$staging_dir/DEBIAN/prerm"
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  remove|upgrade|failed-upgrade|deconfigure) ;;
  *) exit 0 ;;
esac

HELPERD=/usr/local/libexec/securewave-helperd
if [[ -x "$HELPERD" ]] && command -v systemctl >/dev/null 2>&1 &&
   [[ -d /run/systemd/system ]] && systemctl is-active --quiet securewave-helper.service; then
  printf 'version=1\nop=wireguard.cleanup\n' | "$HELPERD" --request >/dev/null
fi

if command -v ip >/dev/null 2>&1 && ip link show dev sw-wg >/dev/null 2>&1; then
  echo "SecureWave WireGuard interface is still active; refusing package removal." >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl disable --now securewave-helper.service
fi
PRERM

cat <<'POSTRM' > "$staging_dir/DEBIAN/postrm"
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  remove|purge)
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      systemctl disable --now securewave-helper.service >/dev/null 2>&1 || true
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    rm -f /etc/systemd/system/securewave-helper.service
    rm -f /usr/lib/tmpfiles.d/securewave-helper.conf
    rm -f /usr/local/libexec/securewave-wg-quick.contract
    rm -f /usr/local/libexec/securewave-helperd
    rm -f /usr/local/libexec/securewave-wg-quick
    rm -f /run/securewave/helper.sock /run/securewave/sw-wg.output-policy
    rm -f /run/securewave/sw-wg.endpoint-ips
    rmdir /run/securewave >/dev/null 2>&1 || true
    ;;
  upgrade|failed-upgrade|abort-install|abort-upgrade|disappear) exit 0 ;;
  *) exit 0 ;;
esac

if [[ "${1:-}" == purge ]]; then
  rm -f /etc/securewave/helper-users
  rmdir /etc/securewave >/dev/null 2>&1 || true
  if getent group securewave >/dev/null 2>&1; then
    groupdel securewave >/dev/null 2>&1 || true
  fi
fi
POSTRM

chmod 0755 "$staging_dir/DEBIAN/preinst" "$staging_dir/DEBIAN/postinst" \
  "$staging_dir/DEBIAN/prerm" "$staging_dir/DEBIAN/postrm"

# dpkg-deb preserves mtimes from the staging tree. Normalize files and
# directories alike so repeated builds from the same source are byte-stable.
find "$staging_dir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

mkdir -p "$output_dir"
dpkg-deb --root-owner-group --build "$staging_dir" "$output_file" >/dev/null
sha256sum "$output_file" > "$output_file.sha256"
if [[ "$source_commit" != "unversioned" ]]; then
  if [[ "$source_tree_state" == "dirty" ]]; then
    tracked_diff_sha256="$({ git -C "$REPO_ROOT" diff --binary HEAD -- . ':!securewave_app/build' ':!static/downloads/*.deb'; git -C "$REPO_ROOT" diff --binary --cached -- . ':!securewave_app/build' ':!static/downloads/*.deb'; } | sha256sum | awk '{print $1}')"
    untracked_files_sha256="$(
      git -C "$REPO_ROOT" ls-files -z --others --exclude-standard -- . ':!securewave_app/build' ':!static/downloads/*.deb' |
        while IFS= read -r -d '' path; do
          [[ -f "$REPO_ROOT/$path" ]] || continue
          printf '%s\0' "$path"
          sha256sum -- "$REPO_ROOT/$path"
        done |
        sha256sum | awk '{print $1}'
    )"
    {
      printf 'commit=%s\n' "$source_commit"
      printf 'dirty=true\n'
      printf 'tracked_diff_sha256=%s\n' "$tracked_diff_sha256"
      printf 'untracked_files_sha256=%s\n' "$untracked_files_sha256"
    } > "$output_file.source-sha256"
  else
    printf 'commit=%s\ndirty=false\n' "$source_commit" > "$output_file.source-sha256"
  fi
fi

echo "OK: Built $output_file"
echo "OK: Package checksum $output_file.sha256"
echo "OK: Local package only; no release artifact was published."
