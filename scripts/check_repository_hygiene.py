#!/usr/bin/env python3
"""Deterministic repository and GitHub workflow hygiene checks."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
ACTION_PIN = re.compile(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)")
IMMUTABLE_ACTION = re.compile(r"^[^/\s]+/[^@\s]+@[0-9a-f]{40}$")
GENERATED_PARTS = {
    ".dart_tool",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "__pycache__",
    "node_modules",
}
GENERATED_SUFFIXES = {".pyc", ".pyo", ".class", ".o", ".obj"}
PACKAGE_SUFFIXES = {".apk", ".deb", ".ipa", ".rpm", ".xcarchive"}
RAW_EVIDENCE_SUFFIXES = {".body", ".headers", ".log", ".out"}
RAW_EVIDENCE_BASELINE = {
    "artifacts/linux-arm64-deb-local-proof/build-after-fix.log",
    "artifacts/linux-arm64-deb-local-proof/install-after-fix.log",
    "artifacts/post-merge-enterprise-release-evidence/bash-syntax.out",
    "artifacts/post-merge-enterprise-release-evidence/compose-dummy-config.out",
    "artifacts/post-merge-enterprise-release-evidence/compose-temp-env-config.out",
    "artifacts/post-merge-enterprise-release-evidence/guardrail-ambiguous-latest.out",
    "artifacts/post-merge-enterprise-release-evidence/guardrail-missing-confirm.out",
    "artifacts/post-merge-enterprise-release-evidence/guardrail-missing-host.out",
    "artifacts/post-merge-enterprise-release-evidence/guardrail-missing-image.out",
    "artifacts/post-merge-enterprise-release-evidence/json-validation.out",
    "artifacts/post-merge-enterprise-release-evidence/live-api-downloads.body",
    "artifacts/post-merge-enterprise-release-evidence/live-api-downloads.headers",
    "artifacts/post-merge-enterprise-release-evidence/live-api-health.body",
    "artifacts/post-merge-enterprise-release-evidence/live-api-health.headers",
    "artifacts/post-merge-enterprise-release-evidence/pytest-downloads-vpn-profile.out",
    "artifacts/post-merge-enterprise-release-evidence/python-compile.out",
}


def tracked_files() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=ROOT
    ).decode("utf-8", errors="surrogateescape")
    return [name for name in output.split("\0") if name]


def check_paths(files: list[str]) -> list[str]:
    failures: list[str] = []
    for name in files:
        path = PurePosixPath(name)
        lowered = name.lower()
        if GENERATED_PARTS.intersection(path.parts) or path.suffix.lower() in GENERATED_SUFFIXES:
            failures.append(f"generated file is tracked: {name}")
        if re.search(r"(?:^|/)\S+ 2(?:\.|$)", name):
            failures.append(f"conflict-copy file is tracked: {name}")
        if lowered.endswith((".env", ".env.local", ".env.production", ".tfstate")):
            if not lowered.endswith((".example", ".sample", ".template")):
                failures.append(f"sensitive runtime file is tracked: {name}")
        if path.suffix.lower() in PACKAGE_SUFFIXES and not name.startswith("static/downloads/"):
            failures.append(f"package artifact is tracked outside static/downloads: {name}")
    raw_files = {
        name
        for name in files
        if name.startswith("artifacts/")
        and PurePosixPath(name).suffix.lower() in RAW_EVIDENCE_SUFFIXES
    }
    for name in sorted(raw_files - RAW_EVIDENCE_BASELINE):
        failures.append(f"new raw evidence file is tracked: {name}")
    return failures


def check_json(files: list[str]) -> list[str]:
    failures: list[str] = []
    for name in files:
        if not (ROOT / name).is_file():
            continue
        if not name.endswith(".json"):
            continue
        try:
            json.loads((ROOT / name).read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            failures.append(f"invalid JSON {name}: {type(exc).__name__}")
    return failures


def check_workflows(files: list[str]) -> list[str]:
    failures: list[str] = []
    workflow_files = [
        name for name in files if name.startswith(".github/workflows/") and name.endswith((".yml", ".yaml"))
    ]
    for name in workflow_files:
        if not (ROOT / name).is_file():
            continue
        lines = (ROOT / name).read_text(encoding="utf-8").splitlines()
        text = "\n".join(lines)
        if "pull_request_target:" in text:
            failures.append(f"unsafe pull_request_target trigger: {name}")
        if not any(line == "permissions:" for line in lines):
            failures.append(f"workflow lacks explicit top-level permissions: {name}")
        for line_number, line in enumerate(lines, start=1):
            match = ACTION_PIN.match(line)
            if not match:
                continue
            reference = match.group(1)
            if reference.startswith("./"):
                continue
            if not IMMUTABLE_ACTION.fullmatch(reference):
                failures.append(
                    f"mutable action reference {name}:{line_number}: {reference}"
                )
            if reference.startswith("actions/upload-artifact@"):
                following = "\n".join(lines[line_number : line_number + 14])
                if "retention-days:" not in following:
                    failures.append(
                        f"artifact upload lacks explicit retention {name}:{line_number}"
                    )
    return failures


def check_container_pins(files: list[str]) -> list[str]:
    failures: list[str] = []
    digest = re.compile(r"@sha256:[0-9a-f]{64}(?:\s|$)")
    for name in files:
        if not (ROOT / name).is_file():
            continue
        path = PurePosixPath(name)
        if "ThirdParty" in path.parts:
            continue
        if path.name == "Dockerfile" or path.name.startswith("Dockerfile."):
            for line_number, line in enumerate(
                (ROOT / name).read_text(encoding="utf-8").splitlines(), start=1
            ):
                if line.startswith("FROM ") and " scratch" not in f" {line}":
                    if not digest.search(line):
                        failures.append(f"unpinned base image {name}:{line_number}")
        if name.startswith(".github/workflows/") and name.endswith((".yml", ".yaml")):
            for line_number, line in enumerate(
                (ROOT / name).read_text(encoding="utf-8").splitlines(), start=1
            ):
                if re.match(r"^\s+image:\s*", line) and not digest.search(line):
                    failures.append(f"unpinned workflow service image {name}:{line_number}")
    return failures


def main() -> int:
    files = tracked_files()
    failures = (
        check_paths(files)
        + check_json(files)
        + check_workflows(files)
        + check_container_pins(files)
    )
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print(
        f"Repository hygiene passed: {len(files)} tracked files, "
        "immutable Actions, valid JSON, and no new raw evidence."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
