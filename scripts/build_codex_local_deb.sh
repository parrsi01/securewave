#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: $0 --api-base http://127.0.0.1:<port>/api --output-dir /external/path" >&2
  exit 2
}

api_base=""
output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base)
      [[ $# -ge 2 ]] || usage
      api_base="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || usage
      output_dir="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$api_base" && -n "$output_dir" ]] || usage
if [[ ! "$api_base" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]+)?/api/?$ ]]; then
  echo "ERROR: --api-base must be an HTTP loopback /api URL." >&2
  exit 2
fi

output_parent="$(dirname "$output_dir")"
if [[ ! -d "$output_parent" ]]; then
  echo "ERROR: --output-dir parent does not exist." >&2
  exit 2
fi
output_dir="$(cd "$output_parent" && pwd)/$(basename "$output_dir")"
case "$output_dir" in
  "$ROOT_DIR"|"$ROOT_DIR"/*)
    echo "ERROR: local package output must be outside the repository." >&2
    exit 2
    ;;
esac

SECUREWAVE_PACKAGE_PROFILE=codex-local \
SECUREWAVE_CODEX_LOCAL=true \
SECUREWAVE_API_BASE_URL="$api_base" \
SECUREWAVE_PACKAGE_OUTPUT_DIR="$output_dir" \
  bash "$ROOT_DIR/securewave_app/scripts/build_deb.sh"
