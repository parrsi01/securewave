#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_dir="$repo_root/securewave_app"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required. Install Flutter and rerun make flutter-run." >&2
  exit 2
}

[[ -d "$app_dir" && -f "$app_dir/pubspec.yaml" ]] || {
  echo "securewave_app/pubspec.yaml is missing; run this from the repository root." >&2
  exit 2
}

api_base="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
[[ "$api_base" =~ ^https?://[^[:space:]]+$ ]] || {
  echo "SECUREWAVE_API_BASE_URL must be an http(s) URL." >&2
  exit 2
}

cd "$app_dir"
flutter pub get
demo_define="${SECUREWAVE_DEMO_MODE:-false}"
exec flutter run -d linux \
  --dart-define="SECUREWAVE_API_BASE_URL=$api_base" \
  --dart-define="SECUREWAVE_DEMO_MODE=$demo_define"
