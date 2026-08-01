#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_dir="$repo_root/securewave_app"

if [[ "${1:-}" == "--install-bundle" ]]; then
  bundle_dir="${2:-}"
  [[ -n "$bundle_dir" && -d "$bundle_dir" ]] || {
    echo "Usage: $0 [--install-bundle <flutter-bundle>]" >&2
    exit 2
  }
  [[ "$(id -u)" -eq 0 ]] || {
    echo "The helper installation phase must run as root." >&2
    exit 2
  }
  helper_installer="$bundle_dir/scripts/install_linux_helper.sh"
  [[ -x "$helper_installer" ]] || {
    echo "Built helper installer is missing: $helper_installer" >&2
    exit 1
  }
  exec "$helper_installer" "$bundle_dir/packaging/linux"
fi

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required to build the Linux helper payload." >&2
  exit 2
}

FORCE_FLUTTER_ENV=true bash "$repo_root/scripts/prepare_flutter_env.sh" >/dev/null
cd "$app_dir"
flutter pub get
flutter build linux --release \
  --dart-define=SECUREWAVE_USE_MOCK_API=false \
  --dart-define=SECUREWAVE_DEBUG_AUTO_LOGIN=false

case "$(uname -m)" in
  x86_64) bundle_arch=x64 ;;
  aarch64|arm64) bundle_arch=arm64 ;;
  *) echo "Unsupported Linux architecture: $(uname -m)" >&2; exit 2 ;;
esac

bundle_dir="$app_dir/build/linux/$bundle_arch/release/bundle"
[[ -d "$bundle_dir" ]] || {
  echo "Flutter Linux bundle not found: $bundle_dir" >&2
  exit 1
}

echo "Installing the contract-13 SecureWave helper requires administrator authentication."
exec sudo "$script_path" --install-bundle "$bundle_dir"
