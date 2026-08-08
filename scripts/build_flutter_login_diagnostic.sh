#!/usr/bin/env bash
set -euo pipefail

# Build an explicitly targeted Linux diagnostic artifact.  This script never
# embeds account credentials, SMTP values, tokens, or approval keys.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/securewave_app"

usage() {
  echo "Usage: $0 --api-base <explicit-https-api-base>" >&2
  exit 2
}

[[ "${1:-}" == "--api-base" && -n "${2:-}" && $# -eq 2 ]] || usage
API_BASE="$2"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not available; diagnostic artifact was not built." >&2
  exit 2
fi

cd "$ROOT_DIR"
if ! python3 - "$API_BASE" <<'PY'
import sys

sys.path.insert(0, "scripts")
from login_diagnostic import normalize_api_base

try:
    normalize_api_base(sys.argv[1])
except Exception:
    raise SystemExit(1)
PY
then
  echo "The diagnostic API base must be an explicit non-local HTTPS /api URL." >&2
  exit 2
fi

cd "$APP_DIR"
flutter build linux --release \
  --dart-define=SECUREWAVE_API_BASE_URL="$API_BASE" \
  --dart-define=SECUREWAVE_USE_MOCK_API=false \
  --dart-define=SECUREWAVE_DIAGNOSTICS=true

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) BUNDLE_ARCH="x64" ;;
  arm64|aarch64) BUNDLE_ARCH="arm64" ;;
  *)
    echo "Unsupported host architecture for the diagnostic artifact." >&2
    exit 2
    ;;
esac

BUNDLE_DIR="$APP_DIR/build/linux/$BUNDLE_ARCH/release/bundle"
[[ -d "$BUNDLE_DIR" ]] || {
  echo "Flutter diagnostic bundle was not produced." >&2
  exit 1
}

OUTPUT_DIR="$APP_DIR/build/login-diagnostic"
OUTPUT="$OUTPUT_DIR/securewave-linux-login-diagnostic-$BUNDLE_ARCH.tar.gz"
if [[ -e "$OUTPUT" ]]; then
  echo "Refusing to overwrite an existing diagnostic artifact: $OUTPUT" >&2
  exit 2
fi
mkdir -p "$OUTPUT_DIR"
tar -czf "$OUTPUT" -C "$BUNDLE_DIR" .
chmod 600 "$OUTPUT"

echo "Flutter login diagnostic artifact created outside public downloads."
echo "Artifact path: $OUTPUT"
