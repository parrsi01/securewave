#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-$ROOT_DIR/packaging/linux}"
HELPER_DIR="/usr/local/libexec"
HELPER_SCRIPT="$HELPER_DIR/securewave-wg-quick"
HELPER_DAEMON="$HELPER_DIR/securewave-helperd"
HELPER_CONTRACT="$HELPER_DIR/securewave-wg-quick.contract"
SOURCE_HELPER_SCRIPT="$SOURCE_DIR/securewave-wg-quick"
SOURCE_HELPER_DAEMON="$SOURCE_DIR/securewave-helperd"
SOURCE_CONTRACT="$SOURCE_DIR/securewave-wg-quick.contract"
SOURCE_SERVICE="$SOURCE_DIR/securewave-helper.service"
SOURCE_TMPFILES="$SOURCE_DIR/securewave-helper.tmpfiles"
SERVICE_FILE="/etc/systemd/system/securewave-helper.service"
TMPFILES_FILE="/usr/lib/tmpfiles.d/securewave-helper.conf"
RUNTIME_GROUP="securewave"
RUNTIME_DIR="/run/securewave"
AUTH_DIR="/etc/securewave"
AUTH_FILE="$AUTH_DIR/helper-users"
OLD_POLKIT_RULE="/etc/polkit-1/rules.d/50-securewave-wg.rules"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "This helper installer must be run as root. Use: sudo $0"
fi

for required in "$SOURCE_HELPER_SCRIPT" "$SOURCE_HELPER_DAEMON" "$SOURCE_CONTRACT" "$SOURCE_SERVICE" "$SOURCE_TMPFILES"; do
  [[ -f "$required" ]] || die "Required SecureWave runtime payload missing: $required"
done

install_apt_dependencies() {
  [[ "${SECUREWAVE_SKIP_DEP_INSTALL:-0}" != "1" ]] || return 0
  command -v apt-get >/dev/null 2>&1 || {
    warn "apt-get not found; skipping automatic dependency install."
    return 0
  }

  local packages=()
  package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'
  }
  command -v wg-quick >/dev/null 2>&1 || packages+=(wireguard-tools)
  command -v openvpn >/dev/null 2>&1 || packages+=(openvpn)
  command -v nmcli >/dev/null 2>&1 || packages+=(network-manager)
  command -v ipsec >/dev/null 2>&1 || packages+=(strongswan)
  package_installed network-manager-strongswan || packages+=(network-manager-strongswan)
  package_installed strongswan-swanctl || packages+=(strongswan-swanctl)
  package_installed strongswan-charon || packages+=(strongswan-charon)
  package_installed libcharon-extra-plugins || packages+=(libcharon-extra-plugins)
  package_installed libstrongswan-extra-plugins || packages+=(libstrongswan-extra-plugins)
  command -v ip >/dev/null 2>&1 || packages+=(iproute2)
  command -v iptables >/dev/null 2>&1 || packages+=(iptables)
  command -v setfacl >/dev/null 2>&1 || packages+=(acl)

  if ((${#packages[@]} == 0)); then
    return 0
  fi

  info "Installing missing Linux VPN runtime packages: ${packages[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${packages[@]}"
}

seed_user() {
  local user="${SECUREWAVE_ALLOWED_USER:-${SUDO_USER:-}}"
  if [[ -z "$user" ]]; then
    user="$(logname 2>/dev/null || true)"
  fi
  if [[ -n "$user" && "$user" != "root" ]]; then
    printf '%s\n' "$user"
  fi
  return 0
}

ensure_runtime_group() {
  if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
    groupadd --system "$RUNTIME_GROUP"
  fi

  install -d -o root -g root -m 0755 "$AUTH_DIR"
  : > "$AUTH_FILE"
  chmod 0644 "$AUTH_FILE"

  add_allowed_user "$(seed_user)"
}

add_allowed_user() {
  local user="$1"
  local uid
  local added=0
  [[ -n "$user" && "$user" != "root" ]] || return 0
  if ! id "$user" >/dev/null 2>&1; then
    warn "SecureWave allowed user '$user' was not found."
    return 0
  fi
  uid="$(id -u "$user")"
  if ! grep -qx "$uid" "$AUTH_FILE" 2>/dev/null; then
    printf '%s\n' "$uid" >> "$AUTH_FILE"
    added=1
  fi
  usermod -a -G "$RUNTIME_GROUP" "$user" || true
  if (( added == 1 )); then
    info "Authorized $user for SecureWave helper socket access."
  fi
}

install_systemd_service() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required for the SecureWave helper service."
  [[ -d /run/systemd/system ]] || die "systemd is required for the SecureWave helper service."

  install -m 0644 "$SOURCE_SERVICE" "$SERVICE_FILE"
  install -m 0644 "$SOURCE_TMPFILES" "$TMPFILES_FILE"
  command -v systemd-tmpfiles >/dev/null 2>&1 && systemd-tmpfiles --create "$TMPFILES_FILE" || true
  systemctl daemon-reload
  systemctl enable --now securewave-helper.service
  systemctl restart securewave-helper.service
}

install_apt_dependencies
ensure_runtime_group

info "Installing SecureWave privileged VPN helper service."
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER_SCRIPT" "$HELPER_SCRIPT"
install -m 0755 "$SOURCE_HELPER_DAEMON" "$HELPER_DAEMON"
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"
install -d -o root -g "$RUNTIME_GROUP" -m 0750 "$RUNTIME_DIR"
rm -f "$OLD_POLKIT_RULE"
install_systemd_service

info "SecureWave Linux VPN helper service installed."
