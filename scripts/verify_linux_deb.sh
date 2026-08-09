#!/usr/bin/env bash
set -euo pipefail

package_path="${1:-}"
if [[ -z "$package_path" || ! -f "$package_path" ]]; then
  echo "Usage: $0 /path/to/securewave-vpn_<version>_<arch>.deb" >&2
  exit 2
fi

for command in dpkg-deb sha256sum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command" >&2
    exit 2
  }
done

control="$(dpkg-deb --info "$package_path")"
contents="$(dpkg-deb --contents "$package_path")"
package_name="$(dpkg-deb --field "$package_path" Package)"
version="$(dpkg-deb --field "$package_path" Version)"
architecture="$(dpkg-deb --field "$package_path" Architecture)"
depends="$(dpkg-deb --field "$package_path" Depends)"

[[ "$package_name" == "securewave-vpn" ]] || {
  echo "ERROR: unexpected package name: $package_name" >&2
  exit 1
}
[[ "$depends" == *"wireguard-tools"* ]] || {
  echo "ERROR: package does not depend on wireguard-tools" >&2
  exit 1
}

for deferred in openvpn strongswan ikev2 network-manager; do
  if printf '%s\n' "$control" "$contents" | grep -Eiq "$deferred"; then
    echo "ERROR: deferred protocol/package reference found: $deferred" >&2
    exit 1
  fi
done

for required_path in \
  ./usr/bin/securewave-vpn \
  ./usr/lib/securewave/securewave_app \
  ./usr/lib/securewave/packaging/linux/securewave-helperd \
  ./usr/lib/securewave/packaging/linux/securewave-wg-quick \
  ./usr/share/securewave/packaging/linux/securewave-helper.service \
  ./usr/share/securewave/packaging/linux/securewave-helper.tmpfiles \
  ./usr/share/securewave/packaging/linux/securewave-wg-quick.contract; do
  printf '%s\n' "$contents" | grep -Fq " $required_path" || {
    echo "ERROR: required package path missing: $required_path" >&2
    exit 1
  }
done

sha256sum "$package_path"
if [[ -f "$package_path.sha256" ]]; then
  sha256sum --check "$package_path.sha256"
fi
if [[ -f "$package_path.source-sha256" ]]; then
  echo "source marker:"
  sed -n '1,4p' "$package_path.source-sha256"
fi

echo "OK: $package_name $version ($architecture) is a WireGuard-only beta package."
echo "OK: static package verification completed; no package was installed."
