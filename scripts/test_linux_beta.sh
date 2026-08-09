#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-$repo_root/.venv/bin/python}"

[[ -x "$python_bin" ]] || { echo "Missing Python test interpreter: $python_bin" >&2; exit 2; }
command -v flutter >/dev/null 2>&1 || { echo "Flutter is required." >&2; exit 2; }

cd "$repo_root"
"$python_bin" -m compileall -q main.py routes services utils models scripts
"$python_bin" -m alembic heads >/dev/null
"$python_bin" -m pytest -q tests

bash -n scripts/run_backend.sh scripts/run_linux_beta.sh scripts/test_linux_beta.sh \
  scripts/build_linux_deb.sh scripts/verify_linux_deb.sh \
  securewave_app/packaging/linux/securewave-wg-quick

cd "$repo_root/securewave_app"
flutter analyze
flutter test
flutter build linux --debug
