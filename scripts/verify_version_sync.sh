#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ ! -f VERSION ]]; then
  fail "VERSION file missing."
fi

version="$(cat VERSION | tr -d '\r' | xargs)"
if [[ -z "$version" ]]; then
  fail "VERSION file is empty."
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
  fail "VERSION must match MAJOR.MINOR.PATCH[+BUILD], got: $version"
fi

pubspec_version="$(awk -F': ' '/^version:/ {print $2}' securewave_app/pubspec.yaml | head -n1 | tr -d '\r')"
if [[ -z "$pubspec_version" ]]; then
  fail "pubspec.yaml missing version: entry."
fi
if [[ "$pubspec_version" != "$version" ]]; then
  fail "pubspec.yaml version ($pubspec_version) != VERSION ($version)"
fi

if [[ -f .env.example.backend ]]; then
  env_version="$(awk -F'=' '/^APP_VERSION=/ {print $2}' .env.example.backend | head -n1 | tr -d '\r')"
  if [[ -n "$env_version" && "$env_version" != "$version" ]]; then
    fail ".env.example.backend APP_VERSION ($env_version) != VERSION ($version)"
  fi
fi

app_version="${version%%+*}"
build_number="0"
if [[ "$version" == *"+"* ]]; then
  build_number="${version##*+}"
fi
info_version="${app_version}.${build_number}"

if [[ ! -f windows_installer/version.iss ]]; then
  fail "windows_installer/version.iss missing. Run scripts/sync_versions.py."
fi

if ! rg -q "#define MyAppVersion \"${app_version}\"" windows_installer/version.iss; then
  fail "windows_installer/version.iss MyAppVersion mismatch (expected ${app_version})."
fi
if ! rg -q "#define MyAppVersionInfo \"${info_version}\"" windows_installer/version.iss; then
  fail "windows_installer/version.iss MyAppVersionInfo mismatch (expected ${info_version})."
fi

echo "OK: version sync verified (${version})."
