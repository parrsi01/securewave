#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-$ROOT_DIR/packaging/linux}"
HELPER_DIR="/usr/local/libexec"
SERVICE_FILE="/etc/systemd/system/securewave-helper.service"
TMPFILES_FILE="/usr/lib/tmpfiles.d/securewave-helper.conf"
RUNTIME_GROUP="securewave"
RUNTIME_DIR="/run/securewave"
AUTH_DIR="/etc/securewave"
AUTH_FILE="$AUTH_DIR/helper-users"

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this installer as root (for example: sudo $0)"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required"
[[ -d /run/systemd/system ]] || die "a running systemd system service manager is required"

for required in wg wg-quick ip iptables nft systemctl; do
  command -v "$required" >/dev/null 2>&1 ||
    die "$required is missing; install the package dependencies before installing the helper"
done

for required_file in \
  securewave-wg-quick \
  securewave-helperd \
  securewave-wg-quick.contract \
  securewave-helper.service \
  securewave-helper.tmpfiles; do
  [[ -f "$SOURCE_DIR/$required_file" ]] ||
    die "required WireGuard runtime payload is missing: $SOURCE_DIR/$required_file"
done

install -d -o root -g root -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_DIR/securewave-wg-quick" "$HELPER_DIR/securewave-wg-quick"
install -m 0755 "$SOURCE_DIR/securewave-helperd" "$HELPER_DIR/securewave-helperd"
install -m 0644 "$SOURCE_DIR/securewave-wg-quick.contract" \
  "$HELPER_DIR/securewave-wg-quick.contract"

if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
  groupadd --system "$RUNTIME_GROUP"
fi

install -d -o root -g root -m 0755 "$AUTH_DIR"
if [[ -e "$AUTH_FILE" || -L "$AUTH_FILE" ]]; then
  [[ -f "$AUTH_FILE" && ! -L "$AUTH_FILE" ]] ||
    die "existing helper allowlist is not a regular file: $AUTH_FILE"
  [[ "$(stat -c %u "$AUTH_FILE" 2>/dev/null || true)" == "0" ]] ||
    die "existing helper allowlist is not root-owned: $AUTH_FILE"
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
systemctl enable --now securewave-helper.service

echo "[OK] SecureWave WireGuard helper installed and running."
echo "[OK] Start a new login session if group membership was changed."
