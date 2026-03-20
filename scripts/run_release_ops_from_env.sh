#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${SECUREWAVE_RELEASE_ENV_FILE:-$HOME/.config/securewave/release.env}"
RUN_RELEASE_OPS_SCRIPT="${RUN_RELEASE_OPS_SCRIPT:-scripts/run_release_ops.sh}"

usage() {
  cat <<'EOF'
Usage: bash scripts/run_release_ops_from_env.sh [--env-file path] [-- <run_release_ops args...>]

Sources a prepared SecureWave release env file and then executes the standard
release operator flow. The env file must not be group/world accessible.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

forward_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a value."
      ENV_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      forward_args+=("$@")
      break
      ;;
    *)
      forward_args+=("$1")
      shift
      ;;
  esac
done

[[ -f "$ENV_FILE" ]] || fail "Release env file not found: $ENV_FILE"
[[ -r "$ENV_FILE" ]] || fail "Release env file is not readable: $ENV_FILE"

perm_octal="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
[[ -n "$perm_octal" ]] || fail "Unable to read permissions for $ENV_FILE"
if (( (10#$perm_octal % 100) != 0 )); then
  fail "Release env file must not be readable by group/other: $ENV_FILE (mode $perm_octal)"
fi

echo "SecureWave release env wrapper"
echo "Env file: $ENV_FILE"
echo "Run script: $RUN_RELEASE_OPS_SCRIPT"
echo

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

exec bash "$RUN_RELEASE_OPS_SCRIPT" "${forward_args[@]}"
