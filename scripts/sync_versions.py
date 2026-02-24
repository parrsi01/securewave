#!/usr/bin/env python3
"""Sync versioned files from the single VERSION source."""
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
PUBSPEC_FILE = ROOT / "securewave_app" / "pubspec.yaml"
ENV_EXAMPLE = ROOT / ".env.example.backend"
INNO_VERSION_FILE = ROOT / "windows_installer" / "version.iss"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


raw_version = VERSION_FILE.read_text(encoding="utf-8").strip() if VERSION_FILE.exists() else ""
if not raw_version:
    fail("VERSION file is missing or empty.")

match = re.fullmatch(r"(\d+\.\d+\.\d+)(?:\+(\d+))?", raw_version)
if not match:
    fail(f"VERSION '{raw_version}' must match MAJOR.MINOR.PATCH[+BUILD].")

app_version = match.group(1)
build_number = match.group(2) or "0"
full_version = raw_version
info_version = f"{app_version}.{build_number}"

# Update pubspec.yaml
if not PUBSPEC_FILE.exists():
    fail(f"pubspec.yaml not found at {PUBSPEC_FILE}")

pubspec_lines = PUBSPEC_FILE.read_text(encoding="utf-8").splitlines()
updated_pubspec = []
found_pubspec = False
for line in pubspec_lines:
    if line.startswith("version:"):
        updated_pubspec.append(f"version: {full_version}")
        found_pubspec = True
    else:
        updated_pubspec.append(line)
if not found_pubspec:
    fail("pubspec.yaml does not contain a version: entry.")
PUBSPEC_FILE.write_text("\n".join(updated_pubspec) + "\n", encoding="utf-8")

# Update .env.example.backend (APP_VERSION)
if ENV_EXAMPLE.exists():
    env_lines = ENV_EXAMPLE.read_text(encoding="utf-8").splitlines()
    updated_env = []
    found_env = False
    for line in env_lines:
        if line.startswith("APP_VERSION="):
            updated_env.append(f"APP_VERSION={full_version}")
            found_env = True
        else:
            updated_env.append(line)
    if not found_env:
        updated_env.append(f"APP_VERSION={full_version}")
    ENV_EXAMPLE.write_text("\n".join(updated_env) + "\n", encoding="utf-8")

# Update Inno Setup version include
INNO_VERSION_FILE.parent.mkdir(parents=True, exist_ok=True)
INNO_VERSION_FILE.write_text(
    "\n".join(
        [
            "; Auto-generated from VERSION. Do not edit.",
            f"#define MyAppVersion \"{app_version}\"",
            f"#define MyAppVersionInfo \"{info_version}\"",
            "",
        ]
    ),
    encoding="utf-8",
)

print(f"Synced versions from VERSION={full_version}")
