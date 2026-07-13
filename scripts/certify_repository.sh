#!/usr/bin/env bash
# Maximum safe local certification. Does not deploy, publish, sign, or use live credentials.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit

PYTHON_BIN="${PYTHON_BIN:-python3}"
FAILURES=0
BLOCKERS=0

run_check() {
  local name="$1"
  shift
  echo "[RUN] $name"
  if "$@"; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

blocked() {
  echo "[BLOCKED] $1" >&2
  BLOCKERS=$((BLOCKERS + 1))
}

run_check "repository hygiene" "$PYTHON_BIN" scripts/check_repository_hygiene.py
run_check "redacted tracked-file secret scan" "$PYTHON_BIN" scripts/scan_repository_secrets.py
run_check "release guards" bash scripts/verify_release_guards.sh
run_check "UI guards" bash scripts/verify_ui_v1.sh
run_check "plan copy" bash scripts/check_plan_copy.sh
run_check "Xcode workspace guards" bash scripts/check_xcworkspace_usage.sh
run_check "Python compile" "$PYTHON_BIN" -m compileall -q \
  main.py routes routers services models database ml scripts infrastructure tests
run_check "backend unit and integration tests" "$PYTHON_BIN" -m pytest -q tests

if "$PYTHON_BIN" -m bandit --version >/dev/null 2>&1; then
  run_check "Bandit high-severity scan" "$PYTHON_BIN" -m bandit -q -lll -r \
    main.py routes routers services models database scripts infrastructure
else
  blocked "Bandit is unavailable; install requirements_dev.txt."
fi

if "$PYTHON_BIN" -m pip_audit --version >/dev/null 2>&1; then
  run_check "Python dependency audit" "$PYTHON_BIN" -m pip_audit -r requirements.txt --strict
else
  blocked "pip-audit is unavailable; install requirements_dev.txt."
fi

shell_files=()
while IFS= read -r -d '' file; do
  shell_files+=("$file")
done < <(git ls-files -z '*.sh')
run_check "tracked shell syntax" bash -n "${shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  run_check "ShellCheck" shellcheck -x "${shell_files[@]}"
else
  blocked "ShellCheck is unavailable."
fi

if command -v actionlint >/dev/null 2>&1; then
  run_check "GitHub Actions lint" actionlint
else
  blocked "actionlint is unavailable; workflow YAML and repository guards still run."
fi

if command -v node >/dev/null 2>&1; then
  while IFS= read -r -d '' file; do
    run_check "JavaScript syntax: $file" node --check "$file"
  done < <(git ls-files -z '*.js')
else
  blocked "Node.js is unavailable; JavaScript syntax was not checked."
fi

if command -v flutter >/dev/null 2>&1; then
  run_check "Prepare non-secret Flutter environment asset" env FORCE_FLUTTER_ENV=true \
    bash scripts/prepare_flutter_env.sh
  run_check "Flutter dependency resolution" bash -c 'cd securewave_app && flutter pub get'
  run_check "Flutter analyze" bash -c 'cd securewave_app && flutter analyze'
  run_check "Flutter tests" bash -c 'cd securewave_app && flutter test --reporter compact'
  if [[ "$(uname -s)" == "Linux" ]]; then
    run_check "Flutter Linux release build" bash -c \
      'cd securewave_app && flutter build linux --release'
  else
    blocked "Flutter Linux release build requires a Linux host."
  fi
  if command -v java >/dev/null 2>&1 && \
    [[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
    run_check "Flutter Android debug build" bash -c \
      'cd securewave_app && flutter build apk --debug'
  else
    blocked "Java and an Android SDK are required for the Flutter Android build."
  fi
else
  blocked "Flutter is unavailable; Flutter checks were not run."
fi

migration_dir="$(mktemp -d -t securewave-certification)"
migration_db="$migration_dir/certification.sqlite"
if AUTO_CREATE_TABLES=false DATABASE_URL="sqlite:///$migration_db" \
  "$PYTHON_BIN" -m alembic upgrade head >/dev/null 2>&1; then
  echo "[PASS] fresh SQLite migration to head"
else
  echo "[FAIL] fresh SQLite migration to head" >&2
  FAILURES=$((FAILURES + 1))
fi
rm -rf "$migration_dir"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  run_check "Docker build check" docker build --check .
  run_check "Docker image build" docker build --tag securewave-certification:local .
else
  blocked "Docker daemon is unavailable; Docker checks were not run."
fi

run_check "git diff check" git diff --check

echo "Certification summary: failures=$FAILURES blockers=$BLOCKERS"
if (( FAILURES > 0 )); then
  exit 1
fi
if (( BLOCKERS > 0 )); then
  exit 2
fi
