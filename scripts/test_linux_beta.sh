#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-$repo_root/.venv/bin/python}"

[[ -x "$python_bin" ]] || {
  echo "ERROR: Python test interpreter not found: $python_bin" >&2
  echo "Create .venv and install requirements.txt plus pytest plugins." >&2
  exit 2
}
command -v flutter >/dev/null 2>&1 || {
  echo "ERROR: Flutter is required for the Linux beta suite." >&2
  exit 2
}

cd "$repo_root"
"$python_bin" -m compileall -q main.py routes services utils models scripts
"$python_bin" -m alembic heads >/dev/null
"$python_bin" -m pytest -q tests

cd "$repo_root/securewave_app"
flutter analyze
flutter test
