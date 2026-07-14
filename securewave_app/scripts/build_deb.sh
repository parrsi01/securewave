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
cp -f "$ROOT_DIR/packaging/linux/securewave-strongswan-routing.conf" "$staging_dir/usr/share/securewave/packaging/linux/securewave-strongswan-routing.conf"
chmod 0755 "$staging_dir/usr/share/securewave/packaging/linux/securewave-wg-quick" \
  "$staging_dir/usr/share/securewave/packaging/linux/securewave-helperd"

cat <<CONTROL > "$staging_dir/DEBIAN/control"
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: wireguard-tools, openvpn, network-manager, network-manager-strongswan, libcharon-extra-plugins, libcharon-extauth-plugins, libstrongswan-extra-plugins, iproute2, iptables, nftables, acl, systemd, systemd-resolved
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

cat <<'PREINST' > "$staging_dir/DEBIAN/preinst"
#!/bin/bash
set -e
case "${1:-}" in
  install|upgrade)
    ;;
  *)
    exit 0
    ;;
esac
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
if charon_nm_running; then
  echo "charon-nm is running; disconnect all NetworkManager strongSwan VPNs before installing SecureWave." >&2
  exit 1
fi
PREINST

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
SOURCE_STRONGSWAN_ROUTING=$SOURCE_DIR/securewave-strongswan-routing.conf
SERVICE_FILE=/etc/systemd/system/securewave-helper.service
TMPFILES_FILE=/usr/lib/tmpfiles.d/securewave-helper.conf
STRONGSWAN_ROUTING_FILE=/etc/strongswan.d/securewave-routing.conf
RUNTIME_GROUP=securewave
RUNTIME_DIR=/run/securewave
AUTH_DIR=/etc/securewave
AUTH_FILE=$AUTH_DIR/helper-users
case "${1:-}" in
  configure)
    ;;
  abort-upgrade|abort-remove|abort-deconfigure)
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl enable --now securewave-helper.service >/dev/null 2>&1 || true
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
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
if charon_nm_running; then
  echo "charon-nm started during installation; disconnect all NetworkManager strongSwan VPNs and reconfigure this package." >&2
  exit 1
fi
if conflict="$(find_strongswan_fwmark_conflict)"; then
  echo "Existing charon-nm routing/mark configuration conflicts with SecureWave: $conflict" >&2
  exit 1
fi
legacy_system_charon_config=0
if [[ -f "$STRONGSWAN_ROUTING_FILE" ]] &&
   grep -Eq '^[[:space:]]*charon[[:space:]]*\{' "$STRONGSWAN_ROUTING_FILE"; then
  legacy_system_charon_config=1
fi
install -d -o root -g root -m 0755 /etc/strongswan.d
install -m 0644 "$SOURCE_STRONGSWAN_ROUTING" "$STRONGSWAN_ROUTING_FILE"
if [[ "$legacy_system_charon_config" == "1" ]]; then
  echo "SecureWave removed its legacy system-charon configuration. If a regular strongSwan daemon was already running, it may retain the old packet marks and pref-220 rule until an administrator-approved restart or reboot. SecureWave did not restart it because doing so could interrupt unrelated IPsec SAs. Review active SAs and restart only during a maintenance window." >&2
fi
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$SOURCE_HELPER" "$HELPER"
install -m 0755 "$SOURCE_HELPERD" "$HELPERD"
install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"

if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
  groupadd --system "$RUNTIME_GROUP"
fi

install -d -o root -g root -m 0755 "$AUTH_DIR"
if [[ -e "$AUTH_FILE" || -L "$AUTH_FILE" ]]; then
  if [[ ! -f "$AUTH_FILE" || -L "$AUTH_FILE" ||
        "$(stat -c %u "$AUTH_FILE" 2>/dev/null || true)" != "0" ]]; then
    echo "Existing SecureWave helper allowlist is not a regular root-owned file: $AUTH_FILE" >&2
    exit 1
  fi
else
  install -o root -g root -m 0644 /dev/null "$AUTH_FILE"
fi
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
set -euo pipefail
HELPER=/usr/local/libexec/securewave-wg-quick
HELPERD=/usr/local/libexec/securewave-helperd
HELPER_CONTRACT=/usr/local/libexec/securewave-wg-quick.contract
case "${1:-}" in
  remove|upgrade|failed-upgrade|deconfigure)
    ;;
  *)
    exit 0
    ;;
esac
response_field() {
  local response="$1"
  local key="$2"
  awk -F= -v key="$key" '
    $1 == key { count++; value = substr($0, length(key) + 2) }
    END {
      if (count == 1) {
        print value
        exit 0
      }
      exit 1
    }
  ' <<< "$response"
}
helper_request() {
  local operation="$1"
  local response
  local expected_contract
  local response_contract
  if [[ ! -f "$HELPER_CONTRACT" || -L "$HELPER_CONTRACT" ]]; then
    echo "SecureWave helper contract is missing or unsafe; refusing package removal." >&2
    return 1
  fi
  if ! expected_contract="$(awk '
      /^[1-9][0-9]{0,9}$/ { valid++; value = $0; next }
      { invalid = 1 }
      END {
        if (valid == 1 && !invalid) {
          print value
          exit 0
        }
        exit 1
      }
    ' "$HELPER_CONTRACT")"; then
    echo "SecureWave helper contract is invalid; refusing package removal." >&2
    return 1
  fi
  if ! response="$(printf 'version=1\nop=%s\n' "$operation" | "$HELPERD" --request)"; then
    echo "SecureWave refused package removal because $operation did not verify cleanly:" >&2
    printf '%s\n' "$response" >&2
    return 1
  fi
  if ! response_contract="$(response_field "$response" contract)" ||
     [[ ! "$response_contract" =~ ^[1-9][0-9]{0,9}$ ]] ||
     [[ "$response_contract" != "$expected_contract" ]]; then
    echo "SecureWave helper returned a missing, malformed, or mismatched cleanup contract; refusing package removal." >&2
    return 1
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
securewave_openvpn_pids() {
  local proc_dir
  for proc_dir in /proc/[0-9]*; do
    [[ -r "$proc_dir/comm" && -r "$proc_dir/cmdline" ]] || continue
    [[ "$(cat "$proc_dir/comm" 2>/dev/null)" == "openvpn" ]] || continue
    [[ "$(stat -c %u "$proc_dir" 2>/dev/null)" == "0" ]] || continue
    if tr '\0' '\n' < "$proc_dir/cmdline" |
       grep -Eq '/(\.config/securewave|run/securewave)/securewave\.ovpn$'; then
      printf '%s\n' "${proc_dir##*/}"
    fi
  done
}
offline_owned_runtime_clean() {
  local connections
  local family
  local ip6tables_rules
  local iptables_rules
  local links
  local routes
  local safe_rule_count
  local -a safe_rule_counts=()
  local rules
  local tables
  command -v ip >/dev/null 2>&1 || return 1
  command -v nmcli >/dev/null 2>&1 || return 1
  command -v nft >/dev/null 2>&1 || return 1
  command -v iptables-save >/dev/null 2>&1 || return 1
  command -v ip6tables-save >/dev/null 2>&1 || return 1
  links="$(ip -o link show)" || return 1
  if awk -F: '
      NF >= 2 {
        name = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        sub(/@.*/, "", name)
        if (name == "sw-wg" || name == "tun-securewave" ||
            name == "nm-xfrm-sw") found = 1
      }
      END { exit found ? 0 : 1 }
    ' <<< "$links"; then
    return 1
  fi
  connections="$(nmcli -t -f NAME,TYPE connection show)" || return 1
  grep -Fqx 'SecureWave-IKEv2:vpn' <<< "$connections" && return 1
  [[ -z "$(securewave_openvpn_pids)" ]] || return 1
  for family in -4 -6; do
    routes="$(ip "$family" -o route show table all)" || return 1
    if awk '
        /(^|[[:space:]])dev[[:space:]]+(sw-wg|tun-securewave|nm-xfrm-sw)([[:space:]]|$)/ {
          found = 1
        }
        END { exit found ? 0 : 1 }
      ' <<< "$routes"; then
      return 1
    fi
    if awk '
        {
          for (i = 1; i < NF; i++) {
            if ($i == "table" && $(i + 1) == "210") {
              found = 1
            }
          }
        }
        END { exit found ? 0 : 1 }
      ' <<< "$routes"; then
      return 1
    fi
    rules="$(ip "$family" -N rule show)" || return 1
    if awk '
        {
          for (i = 1; i < NF; i++) {
            if (($i == "lookup" || $i == "table") && $(i + 1) == "51820") {
              found = 1
            }
          }
        }
        END { exit found ? 0 : 1 }
      ' <<< "$rules"; then
      return 1
    fi
    safe_rule_count="$(awk '
        {
          targets_210 = 0
          for (i = 1; i < NF; i++) {
            if (($i == "lookup" || $i == "table") && $(i + 1) == "210") {
              targets_210 = 1
            }
          }
          if (!targets_210) {
            next
          }
          expected = NF == 8 && $1 == "210:" &&
            ($6 == "0xdc" || $6 == "0xdc/0xffffffff") &&
            ($7 == "lookup" || $7 == "table") && $8 == "210" &&
            (($2 == "not" && $3 == "from" && $4 == "all" && $5 == "fwmark") ||
             ($2 == "from" && $3 == "all" && $4 == "not" && $5 == "fwmark"))
          if (expected) {
            safe++
          } else {
            unexpected = 1
          }
        }
        END {
          if (unexpected || safe > 1) {
            exit 1
          }
          print safe + 0
        }
      ' <<< "$rules")" || return 1
    safe_rule_counts+=("$safe_rule_count")
  done
  [[ "${safe_rule_counts[0]}" == "${safe_rule_counts[1]}" ]] || return 1
  tables="$(nft list tables)" || return 1
  if awk '
      $1 == "table" && ($2 == "ip" || $2 == "ip6" || $2 == "inet") &&
        $3 == "wg-quick-sw-wg" { found = 1 }
      END { exit found ? 0 : 1 }
    ' <<< "$tables"; then
    return 1
  fi
  iptables_rules="$(iptables-save)" || return 1
  grep -Fq 'wg-quick(8) rule for sw-wg' <<< "$iptables_rules" && return 1
  ip6tables_rules="$(ip6tables-save)" || return 1
  grep -Fq 'wg-quick(8) rule for sw-wg' <<< "$ip6tables_rules" && return 1
  [[ ! -e /run/securewave/sw-wg.output-policy &&
     ! -e /run/securewave/sw-wg.endpoint-ips &&
     ! -e /run/securewave/ikev2-xfrm-if-id ]] || return 1
  return 0
}
helper_service_active=0
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  if systemctl is-active --quiet securewave-helper.service; then
    helper_service_active=1
  elif [[ -x "$HELPER" && -x "$HELPERD" ]]; then
    systemctl start securewave-helper.service >/dev/null 2>&1 || true
    if systemctl is-active --quiet securewave-helper.service; then
      helper_service_active=1
    fi
  fi
fi
if [[ "$helper_service_active" == "1" && -x "$HELPER" && -x "$HELPERD" ]]; then
  helper_request wireguard.cleanup
  helper_request ikev2.cleanup
elif ! offline_owned_runtime_clean; then
  echo "SecureWave cleanup service is unavailable and owned runtime state could not be verified clean; refusing package removal." >&2
  exit 1
fi
for proc_dir in /proc/[0-9]*; do
  [[ -r "$proc_dir/comm" && -r "$proc_dir/cmdline" ]] || continue
  [[ "$(cat "$proc_dir/comm" 2>/dev/null)" == "openvpn" ]] || continue
  [[ "$(stat -c %u "$proc_dir" 2>/dev/null)" == "0" ]] || continue
  if tr '\0' '\n' < "$proc_dir/cmdline" | grep -Eq '/(\.config/securewave|run/securewave)/securewave\.ovpn$'; then
    kill -TERM "${proc_dir##*/}" >/dev/null 2>&1 || true
  fi
done
for _ in $(seq 1 40); do
  [[ -z "$(securewave_openvpn_pids)" ]] && break
  sleep 0.25
done
if [[ -n "$(securewave_openvpn_pids)" ]]; then
  echo "SecureWave OpenVPN process remains; refusing package removal." >&2
  exit 1
fi
if [[ -x "$HELPER" ]]; then
  "$HELPER" openvpn-dns-revert
elif ! offline_owned_runtime_clean; then
  echo "SecureWave OpenVPN helper is unavailable and owned runtime state could not be verified clean; refusing package removal." >&2
  exit 1
fi
if ip link show dev tun-securewave >/dev/null 2>&1; then
  echo "SecureWave OpenVPN interface remains; refusing package removal." >&2
  exit 1
fi
for family in -4 -6; do
  routes="$(ip "$family" -o route show table all)"
  if awk '$0 ~ /(^|[[:space:]])dev[[:space:]]+tun-securewave([[:space:]]|$)/ { found = 1 } END { exit found ? 0 : 1 }' <<< "$routes"; then
    echo "SecureWave OpenVPN route remains; refusing package removal." >&2
    exit 1
  fi
done
for _ in $(seq 1 20); do
  charon_nm_running || break
  sleep 0.25
done
if charon_nm_running; then
  echo "charon-nm is still running after SecureWave cleanup; another NetworkManager strongSwan VPN may be active. Refusing to remove shared charon-nm routing configuration." >&2
  exit 1
fi
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  if ! systemctl stop securewave-helper.service; then
    if systemctl is-active --quiet securewave-helper.service; then
      echo "SecureWave helper service could not be stopped; refusing package removal." >&2
      exit 1
    fi
  fi
  systemctl disable securewave-helper.service >/dev/null 2>&1 || true
fi
PRERM

cat <<'POSTRM' > "$staging_dir/DEBIAN/postrm"
#!/bin/bash
set -e
case "${1:-}" in
  remove|purge)
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      systemctl disable --now securewave-helper.service >/dev/null 2>&1 || true
    fi
    rm -f /etc/systemd/system/securewave-helper.service
    rm -f /usr/lib/tmpfiles.d/securewave-helper.conf
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    rm -f /etc/strongswan.d/securewave-routing.conf
    rm -f /run/securewave/helper.sock
    rm -f /run/securewave/sw-wg.output-policy /run/securewave/sw-wg.endpoint-ips
    rm -f /run/securewave/ikev2-xfrm-if-id
    rmdir /run/securewave >/dev/null 2>&1 || true
    rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules
    rm -f /usr/local/libexec/securewave-wg-quick.contract
    rm -f /usr/local/libexec/securewave-helperd
    rm -f /usr/local/libexec/securewave-wg-quick
    ;;
  upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
if [[ "${1:-}" == "purge" ]]; then
  rm -f /etc/securewave/helper-users
  rmdir /etc/securewave >/dev/null 2>&1 || true
  if getent group securewave >/dev/null 2>&1; then
    groupdel securewave >/dev/null 2>&1 || true
  fi
fi
POSTRM
chmod 0755 "$staging_dir/DEBIAN/preinst" "$staging_dir/DEBIAN/postinst" "$staging_dir/DEBIAN/prerm" "$staging_dir/DEBIAN/postrm"

mkdir -p "$output_dir"
output_file="$output_dir/${package_name}_${version}_${arch}.deb"

dpkg-deb --root-owner-group --build "$staging_dir" "$output_file" >/dev/null

echo "OK: Built $output_file"
echo "OK: Local package only; no release artifact was published."
