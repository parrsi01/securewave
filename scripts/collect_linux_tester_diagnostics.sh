#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --package PATH --checksum SHA256 [--output DIR]" >&2
}

package=""
expected_checksum=""
output=""
while (($#)); do
  case "$1" in
    --package) package="${2:-}"; shift 2 ;;
    --checksum) expected_checksum="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! -f "$package" || ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
  usage
  exit 2
fi
expected_checksum="${expected_checksum,,}"
actual_checksum="$(sha256sum "$package" | awk '{print $1}')"
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  echo "Package checksum mismatch; no diagnostic bundle was created." >&2
  exit 1
fi

package_arch="$(dpkg-deb --field "$package" Architecture)"
host_arch="$(dpkg --print-architecture)"
if [[ "$package_arch" != "$host_arch" || ! "$package_arch" =~ ^(amd64|arm64)$ ]]; then
  echo "Unsupported package/host architecture combination: package=$package_arch host=$host_arch" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="securewave-diagnostics-$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [[ -e "$output" ]]; then
  echo "Output path already exists: $output" >&2
  exit 1
fi
install -d -m 0700 "$output"

metadata_dir="$(mktemp -d)"
trap 'rm -rf -- "$metadata_dir"' EXIT
dpkg-deb -x "$package" "$metadata_dir"
release_dir="$metadata_dir/usr/share/securewave/release"
read_release_value() {
  local name="$1"
  local value="unavailable"
  if [[ -f "$release_dir/$name" ]]; then
    value="$(tr -d '\r\n' < "$release_dir/$name")"
  fi
  printf '%s' "$value"
}

source_sha="$(read_release_value source-sha)"
app_version="$(dpkg-deb --field "$package" Version)"
helper_contract="$(read_release_value helper-contract)"
tree_state="$(read_release_value source-tree-state)"

{
  printf 'source_sha=%s\n' "$source_sha"
  printf 'source_tree_state=%s\n' "$tree_state"
  printf 'app_version=%s\n' "$app_version"
  printf 'package_architecture=%s\n' "$package_arch"
  printf 'package_sha256=%s\n' "$actual_checksum"
  printf 'helper_contract=%s\n' "$helper_contract"
  printf 'collected_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output/release-identity.txt"

os_id=unknown
os_version=unknown
if [[ -r /etc/os-release ]]; then
  os_id="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
  os_version="$(. /etc/os-release; printf '%s' "${VERSION_ID:-unknown}")"
fi
libc="$(ldd --version 2>&1 | sed -n '1{s/[[:space:]]\+/ /g;p;}')"
init_system="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"
display_protocol=unknown
if [[ "${XDG_SESSION_TYPE:-}" =~ ^(x11|wayland)$ ]]; then
  display_protocol="$XDG_SESSION_TYPE"
fi
desktop="${XDG_CURRENT_DESKTOP:-unknown}"
desktop="$(printf '%s' "$desktop" | tr -cd '[:alnum:]_.:+-')"
{
  printf 'distribution=%s\n' "$os_id"
  printf 'distribution_version=%s\n' "$os_version"
  printf 'architecture=%s\n' "$host_arch"
  printf 'libc=%s\n' "$libc"
  printf 'init_system=%s\n' "${init_system:-unknown}"
  printf 'display_protocol=%s\n' "$display_protocol"
  printf 'desktop_environment=%s\n' "${desktop:-unknown}"
} > "$output/platform.txt"

if command -v systemctl >/dev/null 2>&1; then
  systemctl show securewave-helper.service \
    --property=LoadState,ActiveState,SubState,UnitFileState \
    --no-pager 2>/dev/null > "$output/helper-service.txt" ||
    printf 'service_state=unavailable\n' > "$output/helper-service.txt"
else
  printf 'service_state=systemctl-unavailable\n' > "$output/helper-service.txt"
fi

if [[ -S /run/securewave/helper.sock ]]; then
  stat -c 'type=socket owner_uid=%u group_gid=%g mode=%a' \
    /run/securewave/helper.sock > "$output/helper-socket.txt"
else
  printf 'socket=absent\n' > "$output/helper-socket.txt"
fi

runtime_contract=unavailable
if [[ -f /usr/local/libexec/securewave-wg-quick.contract ]]; then
  runtime_contract="$(tr -d '\r\n' < /usr/local/libexec/securewave-wg-quick.contract)"
fi
printf 'installed_helper_contract=%s\n' "$runtime_contract" > "$output/helper-contract.txt"

interface_present=false
if [[ -d /sys/class/net/sw-wg ]]; then
  interface_present=true
fi
route_count="$(ip route show table 51820 2>/dev/null | wc -l)"
rule_count="$(ip rule show 2>/dev/null | awk '$0 ~ /lookup 51820/ {count++} END {print count+0}')"
dns_count=0
if command -v resolvectl >/dev/null 2>&1 && [[ "$interface_present" == true ]]; then
  dns_count="$(resolvectl dns sw-wg 2>/dev/null | awk '{print NF > 2 ? NF-2 : 0}')"
fi
latest_handshake=0
rx_bytes=0
tx_bytes=0
if command -v wg >/dev/null 2>&1 && [[ "$interface_present" == true ]]; then
  latest_handshake="$(wg show sw-wg latest-handshakes 2>/dev/null | awk 'max < $2 {max=$2} END {print max+0}')"
  read -r rx_bytes tx_bytes < <(wg show sw-wg transfer 2>/dev/null | awk '{rx+=$2; tx+=$3} END {print rx+0, tx+0}')
fi
{
  printf 'sw_wg_present=%s\n' "$interface_present"
  printf 'table_51820_route_count=%s\n' "$route_count"
  printf 'table_51820_rule_count=%s\n' "$rule_count"
  printf 'dns_server_count=%s\n' "$dns_count"
  printf 'latest_handshake_epoch=%s\n' "$latest_handshake"
  printf 'rx_bytes=%s\n' "$rx_bytes"
  printf 'tx_bytes=%s\n' "$tx_bytes"
} > "$output/wireguard-summary.txt"

chmod 0600 "$output/"*
archive="${output%/}.tar.gz"
tar -czf "$archive" -C "$(dirname "$output")" "$(basename "$output")"
chmod 0600 "$archive"
echo "Created redacted diagnostic bundle: $archive"
