#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-$repo_root/.venv/bin/python}"
mode="${1:-flutter}"

case "$mode" in
  backend)
    [[ -x "$python_bin" ]] || {
      echo "ERROR: Python test interpreter not found: $python_bin" >&2
      exit 2
    }
    cd "$repo_root"
    exec "$python_bin" -m uvicorn main:app \
      --reload \
      --host "${SECUREWAVE_BACKEND_HOST:-127.0.0.1}" \
      --port "${SECUREWAVE_BACKEND_PORT:-8001}"
    ;;
  flutter)
    exec "$repo_root/scripts/run_flutter_linux.sh"
    ;;
  *)
    echo "Usage: $0 [backend|flutter]" >&2
    exit 2
    ;;
esac
