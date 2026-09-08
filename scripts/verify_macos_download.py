#!/usr/bin/env python3
"""Check the published Mac demo's embedded version against its download entry."""

import hashlib
import json
import plistlib
from pathlib import Path
from zipfile import ZipFile


def verify(root: Path) -> None:
    downloads = root / "static" / "downloads"
    manifest = json.loads((downloads / "manifest.json").read_text())
    checked = 0
    for entry in manifest["downloads"]:
        if (entry["platform"] != "macos" or entry["status"] != "available"
                or not entry["filename"].endswith("-ui-demo.zip")):
            continue
        artifact = downloads / entry["filename"]
        with ZipFile(artifact) as archive:
            names = [name for name in archive.namelist()
                     if name.endswith(".app/Contents/Info.plist")]
            if len(names) != 1:
                raise ValueError(f"{artifact.name}: expected exactly one app Info.plist")
            info = plistlib.loads(archive.read(names[0]))
        version = f"{info['CFBundleShortVersionString']}+{info['CFBundleVersion']}"
        if version != entry.get("version"):
            raise ValueError(f"{artifact.name}: binary {version} != manifest {entry.get('version')}")
        checksum = entry.get("checksum_sha256")
        if not checksum or hashlib.sha256(artifact.read_bytes()).hexdigest() != checksum:
            raise ValueError(f"{artifact.name}: missing or mismatched SHA-256")
        checked += 1
        print(f"PASS: {artifact.name}: embedded version {version} and SHA-256 match")
    if not checked:
        raise ValueError("No available macOS demo was verified")


if __name__ == "__main__":
    verify(Path(__file__).resolve().parents[1])
