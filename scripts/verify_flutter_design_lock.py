#!/usr/bin/env python3
"""Fail-closed guard for SecureWave's locked Flutter visual identity."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "securewave_app/lib/ui/sw_theme.dart"
APP = ROOT / "securewave_app/lib/app.dart"
DESIGN_DOC = ROOT / "docs/VPN_APP_DESIGN.md"

REQUIRED = {
    THEME: (
        "static const designSystem = 'securewave-black-blue-v1';",
        "static const background = Color(0xFF03060D);",
        "static const surfaceSecondary = Color(0xFF060C18);",
        "static const surface = Color(0xFF080F20);",
        "static const primary = Color(0xFF00B4FF);",
        "static const secondary = Color(0xFF0066CC);",
        "static const family = 'SpaceGrotesk';",
        "static const mono = 'JetBrainsMono';",
        "static ThemeData get dark",
    ),
    APP: ("theme: SwTheme.dark,",),
    DESIGN_DOC: (
        "#03060d",
        "#060c18",
        "#080f20",
        "#00b4ff",
        "#0066cc",
        "Space Grotesk",
        "JetBrains Mono",
    ),
}

# These are the legacy light/purple identity's distinctive tokens. Keeping the
# deny-list here means a future palette edit fails before it can reach CI or a
# package build, even if the dark theme getter remains wired up.
FORBIDDEN = (
    "0xFFF6FAF7",
    "0xFFEEF5F0",
    "0xFF9B8CF2",
    "0xFF674FD9",
    "0xFFEDE9FD",
    "PlusJakartaSans",
    "SwTheme.light",
    "ColorScheme.light",
    "Colors.purple",
    "deepPurple",
)


def main() -> int:
    failures: list[str] = []
    texts: dict[Path, str] = {}

    for path, needles in REQUIRED.items():
        if not path.is_file():
            failures.append(f"missing required design-lock file: {path.relative_to(ROOT)}")
            continue
        text = path.read_text(encoding="utf-8")
        texts[path] = text
        for needle in needles:
            if needle not in text:
                failures.append(
                    f"{path.relative_to(ROOT)} is missing locked token: {needle}"
                )

    for path in (THEME, APP):
        text = texts.get(path)
        if text is None:
            continue
        for needle in FORBIDDEN:
            if needle in text:
                failures.append(
                    f"{path.relative_to(ROOT)} contains forbidden legacy token: {needle}"
                )

    if failures:
        print("Flutter black/blue design lock FAILED:", file=sys.stderr)
        for failure in failures:
            print(f" - {failure}", file=sys.stderr)
        return 1

    print("Flutter black/blue design lock passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
