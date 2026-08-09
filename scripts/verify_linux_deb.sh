#!/usr/bin/env bash
set -euo pipefail

package_path="${1:-}"
if [[ -z "$package_path" || ! -f "$package_path" ]]; then
  echo "Usage: $0 /path/to/securewave-vpn_<version>_<arch>.deb" >&2
  exit 2
fi

for command in dpkg-deb dpkg dpkg-query sha256sum tar; do
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
[[ "$architecture" == "arm64" ]] || {
  echo "ERROR: Beta 1 package must target arm64, got $architecture" >&2
  exit 1
}
[[ "$depends" == *"wireguard-tools"* ]] || {
  echo "ERROR: package does not depend on wireguard-tools" >&2
  exit 1
}
for required_dependency in libgtk-3-0t64 libsecret-1-0; do
  [[ "$depends" == *"$required_dependency"* ]] || {
    echo "ERROR: package does not depend on $required_dependency" >&2
    exit 1
  }
done

if printf '%s\n' "$control" | grep -Eiq '(^|[ ,])((open|strong|ike|network-manager)[^ ,]*)'; then
  echo "ERROR: package contains a retired networking dependency" >&2
  exit 1
fi

for required_path in \
  ./usr/bin/securewave-vpn \
  ./usr/lib/securewave/securewave_app \
  ./usr/lib/securewave/packaging/linux/securewave-helperd \
  ./usr/lib/securewave/packaging/linux/securewave-wg-quick \
  ./usr/share/securewave/packaging/linux/securewave-helper.service \
  ./usr/share/securewave/packaging/linux/securewave-helper.tmpfiles \
  ./usr/share/securewave/packaging/linux/securewave-wg-quick.contract \
  ./usr/share/securewave/release/app-version \
  ./usr/share/securewave/release/helper-contract \
  ./usr/share/securewave/release/package-architecture \
  ./usr/share/securewave/release/source-sha \
  ./usr/share/securewave/release/source-tree-state; do
  printf '%s\n' "$contents" | grep -Fq " $required_path" || {
    echo "ERROR: required package path missing: $required_path" >&2
    exit 1
  }
done

package_member() {
  dpkg-deb --fsys-tarfile "$package_path" | tar -xOf - "$1"
}

embedded_version="$(package_member ./usr/share/securewave/release/app-version)"
embedded_architecture="$(package_member ./usr/share/securewave/release/package-architecture)"
embedded_contract="$(package_member ./usr/share/securewave/release/helper-contract)"
embedded_source="$(package_member ./usr/share/securewave/release/source-sha)"
embedded_tree_state="$(package_member ./usr/share/securewave/release/source-tree-state)"

[[ "$embedded_version" == "$version" ]] || {
  echo "ERROR: embedded app version does not match package metadata" >&2
  exit 1
}
[[ "$embedded_architecture" == "$architecture" ]] || {
  echo "ERROR: embedded architecture does not match package metadata" >&2
  exit 1
}
[[ "$embedded_contract" == "13" ]] || {
  echo "ERROR: embedded helper contract must be 13" >&2
  exit 1
}
[[ "$embedded_source" =~ ^[0-9a-f]{40}$ ]] || {
  echo "ERROR: embedded source SHA is not a full Git commit" >&2
  exit 1
}
[[ "$embedded_tree_state" == "clean" ]] || {
  echo "ERROR: release candidate was built from a dirty source tree" >&2
  exit 1
}

installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"
if [[ -n "$installed_version" ]] && dpkg --compare-versions "$version" lt "$installed_version"; then
  echo "ERROR: candidate $version would downgrade installed $installed_version" >&2
  exit 1
fi

sha256sum "$package_path"
if [[ -f "$package_path.sha256" ]]; then
  sha256sum --check "$package_path.sha256"
fi
if [[ -f "$package_path.source-sha256" ]]; then
  echo "source marker:"
  sed -n '1,4p' "$package_path.source-sha256"
fi

echo "OK: $package_name $version ($architecture) is the ARM64 WireGuard beta package."
echo "OK: embedded source $embedded_source is marked $embedded_tree_state."
echo "OK: static package verification completed; no package was installed."
