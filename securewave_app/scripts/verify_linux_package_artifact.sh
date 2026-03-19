#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "ERROR: dpkg-deb is required to verify Linux packages." >&2
  exit 1
fi

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [path-to-deb]" >&2
  exit 64
fi

package_path="${1:-}"
if [[ -z "$package_path" ]]; then
  shopt -s nullglob
  candidates=(build/packaging/*.deb)
  shopt -u nullglob
  if [[ "${#candidates[@]}" -ne 1 ]]; then
    echo "ERROR: expected exactly one .deb under build/packaging or pass a path explicitly." >&2
    exit 1
  fi
  package_path="${candidates[0]}"
fi

if [[ ! -f "$package_path" ]]; then
  echo "ERROR: package not found: $package_path" >&2
  exit 1
fi

expect_in_text() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    echo "ERROR: missing $label: $needle" >&2
    exit 1
  fi
}

control_fields="$(dpkg-deb -f "$package_path")"
listing="$(dpkg-deb -c "$package_path")"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
dpkg-deb -e "$package_path" "$temp_dir/control"

expect_in_text "$control_fields" "Package: securewave-vpn" "package name"
expect_in_text "$control_fields" "Depends: wireguard-tools, policykit-1" "package dependency set"
expect_in_text "$listing" "./usr/bin/securewave-vpn" "launcher wrapper"
expect_in_text "$listing" "./usr/lib/securewave/securewave_app" "release binary"
expect_in_text "$listing" "./usr/share/applications/securewave-vpn.desktop" "desktop entry"
expect_in_text "$listing" "root/root" "root ownership"

postinst_path="$temp_dir/control/postinst"
postrm_path="$temp_dir/control/postrm"
if [[ ! -f "$postinst_path" || ! -f "$postrm_path" ]]; then
  echo "ERROR: package control scripts are missing postinst/postrm." >&2
  exit 1
fi

postinst_text="$(cat "$postinst_path")"
postrm_text="$(cat "$postrm_path")"

expect_in_text "$postinst_text" "/usr/local/libexec/securewave-wg-quick" "helper install path"
expect_in_text "$postinst_text" "securewave-wg-quick.contract" "helper contract path"
expect_in_text "$postinst_text" "50-securewave-wg.rules" "polkit rule path"
expect_in_text "$postrm_text" "rm -f /usr/local/libexec/securewave-wg-quick" "helper cleanup"
expect_in_text "$postrm_text" "securewave-wg-quick.contract" "helper contract cleanup"
expect_in_text "$postrm_text" "50-securewave-wg.rules" "polkit cleanup"

echo "OK: verified Linux package artifact $package_path"
