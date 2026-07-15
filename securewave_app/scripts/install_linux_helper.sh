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
SOURCE_STRONGSWAN_ROUTING="$SOURCE_DIR/securewave-strongswan-routing.conf"
SERVICE_FILE="/etc/systemd/system/securewave-helper.service"
TMPFILES_FILE="/usr/lib/tmpfiles.d/securewave-helper.conf"
STRONGSWAN_ROUTING_FILE="/etc/strongswan.d/securewave-routing.conf"
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

for required in "$SOURCE_HELPER_SCRIPT" "$SOURCE_HELPER_DAEMON" "$SOURCE_CONTRACT" "$SOURCE_SERVICE" "$SOURCE_TMPFILES" "$SOURCE_STRONGSWAN_ROUTING"; do
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
  command -v resolvectl >/dev/null 2>&1 || packages+=(systemd-resolved)
  package_installed network-manager-strongswan || packages+=(network-manager-strongswan)
  package_installed strongswan-nm || packages+=(strongswan-nm)
  package_installed strongswan || packages+=(strongswan)
  package_installed strongswan-swanctl || packages+=(strongswan-swanctl)
  package_installed strongswan-charon || packages+=(strongswan-charon)
  package_installed libcharon-extra-plugins || packages+=(libcharon-extra-plugins)
  package_installed libcharon-extauth-plugins || packages+=(libcharon-extauth-plugins)
  package_installed libstrongswan-standard-plugins || packages+=(libstrongswan-standard-plugins)
  package_installed libstrongswan-extra-plugins || packages+=(libstrongswan-extra-plugins)
  command -v ip >/dev/null 2>&1 || packages+=(iproute2)
  command -v iptables >/dev/null 2>&1 || packages+=(iptables)
  command -v nft >/dev/null 2>&1 || packages+=(nftables)
  command -v setfacl >/dev/null 2>&1 || packages+=(acl)

  if ((${#packages[@]} == 0)); then
    return 0
  fi

  info "Installing missing Linux VPN runtime packages: ${packages[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${packages[@]}"
}

strongswan_file_has_charon_nm_routing_settings() {
  awk '
    BEGIN { depth = 0; nm_depth = 0; pending_nm = 0; found = 0 }
    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") {
        next
      }
      if (line ~ /^charon-nm[.].*(fwmark|routing_table|routing_table_prio)[[:space:]]*=/) {
        found = 1
      }
      if (line ~ /^charon-nm[[:space:]]*\{/) {
        nm_depth = depth + 1
        pending_nm = 0
      } else if (line == "charon-nm") {
        pending_nm = 1
      } else if (pending_nm && line ~ /^\{/) {
        nm_depth = depth + 1
        pending_nm = 0
      } else if (pending_nm) {
        pending_nm = 0
      }
      if (nm_depth > 0 &&
          line ~ /(^|[.[:space:]])(fwmark|routing_table|routing_table_prio)[[:space:]]*=/) {
        found = 1
      }
      if (nm_depth > 0 && line ~ /^include[[:space:]]+/) {
        found = 1
      }
      braces = line
      opens = gsub(/\{/, "{", braces)
      braces = line
      closes = gsub(/\}/, "}", braces)
      depth += opens - closes
      if (nm_depth > 0 && depth < nm_depth) {
        nm_depth = 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

find_strongswan_fwmark_conflict() {
  local candidate
  local candidates=()

  [[ -f /etc/strongswan.conf ]] && candidates+=(/etc/strongswan.conf)
  if [[ -d /etc/strongswan.d ]]; then
    while IFS= read -r -d '' candidate; do
      candidates+=("$candidate")
    done < <(find /etc/strongswan.d -type f -name '*.conf' -print0)
  fi

  for candidate in "${candidates[@]}"; do
    [[ "$candidate" != "$STRONGSWAN_ROUTING_FILE" ]] || continue
    if strongswan_file_has_charon_nm_routing_settings "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_strongswan_routing_config() {
  local conflict
  local legacy_system_charon_config=0
  if conflict="$(find_strongswan_fwmark_conflict)"; then
    die "Existing charon-nm routing/mark configuration conflicts with SecureWave: $conflict"
  fi

  if [[ -f "$STRONGSWAN_ROUTING_FILE" ]] &&
     grep -Eq '^[[:space:]]*charon[[:space:]]*\{' "$STRONGSWAN_ROUTING_FILE"; then
    legacy_system_charon_config=1
  fi
  install -d -o root -g root -m 0755 /etc/strongswan.d
  install -m 0644 "$SOURCE_STRONGSWAN_ROUTING" "$STRONGSWAN_ROUTING_FILE"
  if [[ "$legacy_system_charon_config" == "1" ]]; then
    warn "SecureWave removed its legacy system-charon configuration. If a regular strongSwan daemon was already running, it may retain the old packet marks and pref-220 rule until an administrator-approved restart or reboot. SecureWave did not restart it because doing so could interrupt unrelated IPsec SAs. Review active SAs and restart only during a maintenance window."
  fi
}

charon_nm_running() {
  local proc_dir
  local process_name
  local process_owner
  local process_exe
  for proc_dir in /proc/[0-9]*; do
    [[ -r "$proc_dir/comm" && -L "$proc_dir/exe" ]] || continue
    IFS= read -r process_name < "$proc_dir/comm" || continue
    [[ "$process_name" == "charon-nm" ]] || continue
    process_owner="$(stat -c %u "$proc_dir" 2>/dev/null || true)"
    [[ "$process_owner" == "0" ]] || continue
    process_exe="$(readlink "$proc_dir/exe" 2>/dev/null || true)"
    [[ "$process_exe" == "/usr/lib/ipsec/charon-nm" ||
       "$process_exe" == "/usr/lib/ipsec/charon-nm (deleted)" ]] && return 0
  done
  return 1
}

preflight_install() {
  local conflict
  command -v systemctl >/dev/null 2>&1 ||
    die "systemctl is required for the SecureWave helper service."
  [[ -d /run/systemd/system ]] ||
    die "systemd is required for the SecureWave helper service."
  if charon_nm_running; then
    die "charon-nm is running; disconnect all NetworkManager strongSwan VPNs before installing the helper."
  fi
  if conflict="$(find_strongswan_fwmark_conflict)"; then
    die "Existing charon-nm routing/mark configuration conflicts with SecureWave: $conflict"
  fi
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
  if [[ -e "$AUTH_FILE" || -L "$AUTH_FILE" ]]; then
    if [[ ! -f "$AUTH_FILE" || -L "$AUTH_FILE" ||
          "$(stat -c %u "$AUTH_FILE" 2>/dev/null || true)" != "0" ]]; then
      die "Existing SecureWave helper allowlist is not a regular root-owned file: $AUTH_FILE"
    fi
  else
    install -o root -g root -m 0644 /dev/null "$AUTH_FILE"
  fi
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
  if command -v systemd-tmpfiles >/dev/null 2>&1; then
    systemd-tmpfiles --create "$TMPFILES_FILE" || true
  fi
  systemctl daemon-reload
  systemctl enable --now securewave-helper.service
  systemctl restart securewave-helper.service
}

preflight_install
install_apt_dependencies
preflight_install
ensure_runtime_group
install_strongswan_routing_config

info "Installing SecureWave privileged VPN helper service."
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER_SCRIPT" "$HELPER_SCRIPT"
install -m 0755 "$SOURCE_HELPER_DAEMON" "$HELPER_DAEMON"
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"
install -d -o root -g "$RUNTIME_GROUP" -m 0750 "$RUNTIME_DIR"
rm -f "$OLD_POLKIT_RULE"
install_systemd_service

info "SecureWave Linux VPN helper service installed."
