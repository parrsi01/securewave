#!/usr/bin/env python3
"""Refresh static download manifest truth from files on disk."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS_DIR = ROOT / "static" / "downloads"
MANIFEST_PATH = DOWNLOADS_DIR / "manifest.json"
CHECKSUMS_PATH = DOWNLOADS_DIR / "checksums.txt"

CATALOG = [
    {
        "platform": "macos",
        "architecture": "universal",
        "filename": "securewave-apple-release-handoff.zip",
        "url": "/downloads/securewave-apple-release-handoff.zip",
        "notes": "Mac/Xcode handoff kit for producing the signed macOS/iOS archive. Not a notarized app bundle.",
    },
    {
        "platform": "macos",
        "architecture": "arm64",
        "filename": "securewave-macos-arm64-ui-demo.zip",
        "url": "/downloads/securewave-macos-arm64-ui-demo.zip",
        "notes": "macOS UI demo app package. Build this on an Apple Silicon Mac with securewave_app/scripts/package_macos_ui_demo.sh; VPN tunneling is not enabled in the macOS demo.",
    },
    {
        "platform": "macos",
        "architecture": "x64",
        "filename": "securewave-macos-x64-ui-demo.zip",
        "url": "/downloads/securewave-macos-x64-ui-demo.zip",
        "notes": "macOS UI demo app package. Build this on an Intel Mac with securewave_app/scripts/package_macos_ui_demo.sh; VPN tunneling is not enabled in the macOS demo.",
    },
    {
        "platform": "windows",
        "architecture": "x64",
        "filename": "securewave-windows-x64-setup.exe",
        "url": "/downloads/securewave-windows-x64-setup.exe",
        "notes": "Windows installer appears here after the Windows release runner publishes it.",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.deb",
        "url": "/downloads/securewave-linux-x64.deb",
        "supports_full_routing": True,
        "notes": "Debian/Ubuntu package with the root-owned SecureWave helper service for full no-prompt VPN routing.",
    },
    {
        "platform": "linux",
        "architecture": "arm64",
        "filename": "securewave-linux-arm64.deb",
        "url": "/downloads/securewave-linux-arm64.deb",
        "supports_full_routing": True,
        "notes": "Debian/Ubuntu ARM64 package with the root-owned SecureWave helper service for full no-prompt VPN routing.",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.AppImage",
        "url": "/downloads/securewave-linux-x64.AppImage",
        "supports_full_routing": False,
        "notes": "Portable Linux UI AppImage. It can use full no-prompt VPN routing only when the SecureWave .deb helper service is already installed.",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.tar.gz",
        "url": "/downloads/securewave-linux-x64.tar.gz",
        "supports_full_routing": False,
        "notes": "Portable Linux UI tarball. It can use full no-prompt VPN routing only when the SecureWave .deb helper service is already installed.",
    },
    {
        "platform": "linux",
        "architecture": "arm64",
        "filename": "securewave-app-linux-arm64.zip",
        "url": "/downloads/securewave-app-linux-arm64.zip",
        "supports_full_routing": False,
        "notes": "Portable Linux ARM64 UI zip. It can use full no-prompt VPN routing only when the SecureWave .deb helper service is already installed.",
    },
    {
        "platform": "android",
        "architecture": "universal",
        "filename": "securewave-android.apk",
        "url": "/downloads/securewave-android.apk",
        "notes": "Android APK appears here after the Android release runner publishes it.",
    },
    {
        "platform": "ios",
        "architecture": "arm64",
        "filename": "",
        "url": "#",
        "notes": "iOS is distributed through TestFlight/App Store after Apple Network Extension approval.",
    },
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def format_size(size_bytes: int) -> str:
    if size_bytes < 1024:
        return f"{size_bytes} B"
    if size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    if size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


def build_manifest() -> dict:
    downloads = []
    checksum_lines = []
    for item in CATALOG:
        entry = dict(item)
        filename = entry.get("filename") or ""
        path = DOWNLOADS_DIR / filename if filename else None
        exists = bool(path and path.is_file())
        entry["status"] = "available" if exists else "coming_soon"
        if not exists and entry.get("url") != "#":
            entry["url"] = "#"
        if exists and path is not None:
            size = path.stat().st_size
            digest = sha256_file(path)
            entry["size_bytes"] = size
            entry["size_display"] = format_size(size)
            entry["sha256"] = digest
            checksum_lines.append(f"{digest}  {filename}")
        downloads.append(entry)
    return {"version": "1.0.0", "downloads": downloads}, checksum_lines


def main() -> int:
    DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
    manifest, checksum_lines = build_manifest()
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    CHECKSUMS_PATH.write_text("\n".join(sorted(checksum_lines)) + "\n", encoding="utf-8")
    print(f"OK: updated {MANIFEST_PATH}")
    print(f"OK: updated {CHECKSUMS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
