#!/usr/bin/env bash
# Safe, local-only full application baseline. It never deploys, publishes,
# signs, contacts live VPN hosts, or runs packaging installers.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

run() {
  printf '\n==> '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: required baseline tool is not available: $command_name" >&2
    exit 1
  fi
}

for command_name in git python3 bash node docker flutter; do
  require_command "$command_name"
done

mapfile -d '' -t python_files < <(git ls-files -z -- '*.py')
mapfile -d '' -t shell_files < <(git ls-files -z -- '*.sh')
mapfile -d '' -t website_js_files < <(git ls-files -z -- 'static/js/*.js')

if (( ${#python_files[@]} == 0 || ${#shell_files[@]} == 0 )); then
  echo "ERROR: tracked Python or shell sources were not found." >&2
  exit 1
fi

# Compile tracked source only. This avoids treating local virtual environments
# and unrelated untracked trees as application code.
run python3 -B -m compileall -q "${python_files[@]}"

# Existing project-owned checks.
run bash scripts/verify_env.sh
run bash scripts/run_backend_tests.sh
run bash scripts/verify_website.sh
run bash scripts/verify_ui_v1.sh
run bash scripts/verify_release_guards.sh
run bash scripts/check_xcworkspace_usage.sh
run bash -n "${shell_files[@]}"

for file in "${website_js_files[@]}"; do
  run node --check "$file"
done
run node -e "JSON.parse(require('node:fs').readFileSync('static/downloads/manifest.json', 'utf8')); console.log('downloads manifest JSON valid')"

# Compose interpolation/syntax only. Dummy values prevent reading a real env
# file and this command never starts containers.
run env POSTGRES_PASSWORD=baseline-not-a-secret SECUREWAVE_IMAGE=securewave:baseline SECUREWAVE_ENV_FILE=/dev/null docker compose -f deploy/hetzner/compose.yaml config --quiet

# Flutter's generated .env is ignored and is only created when absent; the
# helper script never overwrites a local file unless explicitly forced.
run bash scripts/prepare_flutter_env.sh
pushd securewave_app >/dev/null
run flutter pub get
run flutter analyze
run flutter test
run flutter build linux --debug
popd >/dev/null

echo ""
echo "Full local baseline completed. This is not deployment, package-install,"
echo "live-VPN, signing, SMTP, or release-readiness evidence."
