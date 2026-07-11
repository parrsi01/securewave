#!/usr/bin/env python3
"""Scan tracked source/config files without printing matched secret values."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
SOURCE_SUFFIXES = {
    "",
    ".conf",
    ".dart",
    ".env",
    ".ini",
    ".js",
    ".json",
    ".kts",
    ".plist",
    ".py",
    ".sh",
    ".swift",
    ".tf",
    ".toml",
    ".xml",
    ".yaml",
    ".yml",
}
SKIP_PARTS = {"ThirdParty", "artifacts", "docs", "tests", "securewave-tests"}
SKIP_FILES = {
    "scripts/pre-commit-hook.sh",
    "scripts/scan_repository_secrets.py",
}
PLACEHOLDER_WORDS = (
    "change-me",
    "dummy",
    "example",
    "placeholder",
    "test-secret",
    "your_",
    "your-",
)
PATTERNS = {
    "private_key": re.compile(rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"),
    "aws_access_key": re.compile(rb"AKIA[0-9A-Z]{16}"),
    "stripe_live_key": re.compile(rb"sk_live_[0-9A-Za-z]{24,}"),
    "sendgrid_key": re.compile(rb"SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}"),
    "github_token": re.compile(rb"gh[oprsu]_[A-Za-z0-9]{30,}"),
    "credential_url": re.compile(
        rb"(?i)(?:postgres|mysql|mongodb(?:\+srv)?)://[^:\s]+:[^@\s]+@"
    ),
}


def tracked_files() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=ROOT
    ).decode("utf-8", errors="surrogateescape")
    return [name for name in output.split("\0") if name]


def should_scan(name: str) -> bool:
    path = PurePosixPath(name)
    return (
        name not in SKIP_FILES
        and not SKIP_PARTS.intersection(path.parts)
        and path.suffix.lower() in SOURCE_SUFFIXES
    )


def main() -> int:
    findings: list[tuple[str, str, int]] = []
    for name in tracked_files():
        if not should_scan(name):
            continue
        path = ROOT / name
        try:
            data = path.read_bytes()
        except OSError:
            continue
        lowered = data.lower()
        for kind, pattern in PATTERNS.items():
            for match in pattern.finditer(data):
                line_start = data.rfind(b"\n", 0, match.start()) + 1
                line_end = data.find(b"\n", match.end())
                if line_end < 0:
                    line_end = len(data)
                line = lowered[line_start:line_end]
                if any(word.encode() in line for word in PLACEHOLDER_WORDS):
                    continue
                line_number = data.count(b"\n", 0, match.start()) + 1
                findings.append((name, kind, line_number))
    if findings:
        for name, kind, line_number in findings:
            print(f"ERROR: potential {kind} in {name}:{line_number}", file=sys.stderr)
        return 1
    print("Tracked source/config secret scan passed; matched values are never printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
