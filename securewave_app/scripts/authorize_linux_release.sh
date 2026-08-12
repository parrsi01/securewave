#!/usr/bin/env bash
set -euo pipefail

repo_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
expected_branch="codex/linux-runtime-final"

block() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 1
}

[[ "$(uname -s)" == "Linux" ]] || block "Linux is required for release packaging."
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) block "ARM64 is required for release packaging." ;;
esac

[[ "${SECUREWAVE_PACKAGE_PROFILE:-}" == "production" ]] ||
  block "The production package profile is required."
[[ "${DEMO_MODE:-}" == "false" ]] || block "DEMO_MODE must be explicitly false."
[[ "${WG_MOCK_MODE:-}" == "false" ]] || block "WG_MOCK_MODE must be explicitly false."
[[ "${SECUREWAVE_USE_MOCK_API:-}" == "false" ]] ||
  block "SECUREWAVE_USE_MOCK_API must be explicitly false."

api_url="${SECUREWAVE_API_BASE_URL:-}"
[[ "$api_url" == https://* ]] ||
  block "The API target must use HTTPS and the approved /api path."
authority_and_path="${api_url#https://}"
[[ "$authority_and_path" == */* ]] ||
  block "The API target must use HTTPS and the approved /api path."
authority="${authority_and_path%%/*}"
api_path="${authority_and_path#*/}"
[[ "$api_path" == "api" || "$api_path" == "api/" ]] ||
  block "The API target must use HTTPS and the approved /api path."
[[ "$authority" =~ ^[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] ||
  block "The API target authority is invalid."
api_host="${authority%%:*}"
case "${api_host,,}" in
  localhost|localhost.*|127.*|0.0.0.0|*.local)
    block "The API target must not be local or loopback."
    ;;
esac

head_sha="$(git -C "$repo_dir" rev-parse --verify HEAD 2>/dev/null)" ||
  block "The release candidate HEAD is unavailable."
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] ||
  block "The release candidate HEAD is malformed."

branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
  block "Release packaging requires an attached branch."
[[ "$branch" == "$expected_branch" ]] ||
  block "Release packaging requires the authorized release branch."

candidate_sha="${SECUREWAVE_RELEASE_CANDIDATE_SHA:-}"
[[ "$candidate_sha" =~ ^[0-9a-f]{40}$ ]] ||
  block "The authorized candidate SHA is missing or malformed."
[[ "$candidate_sha" == "$head_sha" ]] ||
  block "The authorized candidate SHA does not match HEAD."

[[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=all)" ]] ||
  block "The release candidate worktree is not clean."

authorization="${SECUREWAVE_RELEASE_AUTHORIZATION:-}"
[[ -n "$authorization" ]] || block "Explicit release authorization is required."
[[ "$authorization" == "approve:${expected_branch}:${head_sha}" ]] ||
  block "Release authorization is malformed or mismatched."

echo "OK: release source authorized for Linux ARM64 production packaging."
