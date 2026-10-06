#!/usr/bin/env python3
"""Check current versions and local Markdown destinations, without network I/O."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def main():
    errors = []
    if (ROOT / "VERSION").read_text().strip() != "1.0.0":
        errors.append("VERSION must be 1.0.0")
    if not re.search(r"^version: 1\.0\.0$", (ROOT / "securewave_app/pubspec.yaml").read_text(), re.M):
        errors.append("Flutter version must be 1.0.0")
    if 'DEFAULT_APP_VERSION = "1.0.0"' not in (ROOT / "release_metadata.py").read_text():
        errors.append("Backend default version must be 1.0.0")
    files = [ROOT / "README.md", ROOT / "QUICK_START.md", ROOT / "securewave_app/README.md",
             *(ROOT / "docs").rglob("*.md")]
    for file in files:
        if file.name == "linux-release-status.md":  # Preserved ignored private-era local note.
            continue
        text = re.sub(r"```.*?```", "", file.read_text(), flags=re.S)
        for match in re.finditer(r"!?\[[^\]]*\]\(([^)]+)\)", text):
            target = match.group(1).split(' "', 1)[0].strip("<>")
            parts = urlsplit(target)
            if parts.scheme or parts.netloc or not parts.path:
                continue
            destination = (file.parent / unquote(parts.path)).resolve()
            if not destination.exists():
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{file.relative_to(ROOT)}:{line}: missing {target}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Versions and local destinations checked in {len(files)} Markdown files.")


if __name__ == "__main__":
    main()
