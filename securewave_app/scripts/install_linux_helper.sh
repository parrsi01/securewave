#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-$ROOT_DIR/packaging/linux}"
HELPER_DIR="/usr/local/libexec"
HELPER="$HELPER_DIR/securewave-wg-quick"
HELPER_CONTRACT="$HELPER_DIR/securewave-wg-quick.contract"
SOURCE_HELPER="$SOURCE_DIR/securewave-wg-quick"
SOURCE_CONTRACT="$SOURCE_DIR/securewave-wg-quick.contract"
SOURCE_POLKIT_RULE="$SOURCE_DIR/50-securewave-wg.rules"
POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
POLKIT_RULE="$POLKIT_RULES_DIR/50-securewave-wg.rules"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "This helper installer must be run as root. Use: sudo $0"
fi

for required in "$SOURCE_HELPER" "$SOURCE_CONTRACT" "$SOURCE_POLKIT_RULE"; do
  [[ -f "$required" ]] || die "Required SecureWave runtime payload missing: $required"
done

install_apt_dependencies() {
  [[ "${SECUREWAVE_SKIP_DEP_INSTALL:-0}" != "1" ]] || return 0
  command -v apt-get >/dev/null 2>&1 || {
    warn "apt-get not found; skipping automatic dependency install."
    return 0
  }

  local packages=()
  command -v wg-quick >/dev/null 2>&1 || packages+=(wireguard-tools)
  command -v openvpn >/dev/null 2>&1 || packages+=(openvpn)
  command -v nmcli >/dev/null 2>&1 || packages+=(network-manager)
  command -v ipsec >/dev/null 2>&1 || packages+=(strongswan network-manager-strongswan)
  command -v pkexec >/dev/null 2>&1 || packages+=(policykit-1)

  if ((${#packages[@]} == 0)); then
    return 0
  fi

  info "Installing missing Linux VPN runtime packages: ${packages[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${packages[@]}"
}

render_polkit_rule() {
  local allow_user="${SECUREWAVE_ALLOWED_USER:-${SUDO_USER:-}}"
  if [[ -z "$allow_user" ]]; then
    allow_user="$(logname 2>/dev/null || true)"
  fi

  mkdir -p "$POLKIT_RULES_DIR"
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

install_apt_dependencies

info "Installing SecureWave privileged VPN helper."
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER" "$HELPER"
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"
render_polkit_rule
reload_polkit

info "SecureWave Linux VPN helper installed."
