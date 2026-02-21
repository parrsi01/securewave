import json

import routes.downloads as downloads


def test_downloads_endpoint_uses_manifest_and_file_presence(client, monkeypatch, tmp_path):
    artifact = tmp_path / "securewave-linux-x64-9.9.9.deb"
    artifact.write_bytes(b"deb-test")

    manifest = {
        "version": "9.9.9",
        "build_date": "2026-02-21T00:00:00Z",
        "provider": "hetzner",
        "artifacts": [
            {
                "platform": "linux",
                "architecture": "x64",
                "format": "deb",
                "filename": artifact.name,
                "url": f"/downloads/{artifact.name}",
                "status": "available",
                "primary": True,
                "sha256": "deadbeef",
                "notes": "Linux package",
            },
            {
                "platform": "windows",
                "architecture": "x64",
                "format": "exe",
                "filename": "",
                "url": None,
                "status": "unavailable",
                "primary": True,
                "notes": "Not published",
            },
        ],
    }
    manifest_path = tmp_path / "version.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    monkeypatch.setattr(downloads, "DOWNLOADS_DIR", tmp_path)
    monkeypatch.setattr(downloads, "MANIFEST_PATH", manifest_path)

    response = client.get("/api/downloads")
    assert response.status_code == 200

    payload = response.json()
    assert payload["version"] == "9.9.9"
    assert payload["build_date"] == "2026-02-21T00:00:00Z"

    entries = payload["downloads"]
    assert len(entries) == 2

    linux_entry = next(entry for entry in entries if entry["platform"] == "linux")
    assert linux_entry["status"] == "available"
    assert linux_entry["url"] == f"/downloads/{artifact.name}"
    assert linux_entry["size_bytes"] == len(b"deb-test")

    windows_entry = next(entry for entry in entries if entry["platform"] == "windows")
    assert windows_entry["status"] == "unavailable"
    assert windows_entry["url"] is None


def test_detect_endpoint_prefers_primary_artifact(client, monkeypatch, tmp_path):
    primary_file = tmp_path / "securewave-linux-primary.deb"
    fallback_file = tmp_path / "securewave-linux-fallback.deb"
    primary_file.write_bytes(b"primary")
    fallback_file.write_bytes(b"fallback")

    manifest = {
        "version": "9.9.9",
        "provider": "hetzner",
        "artifacts": [
            {
                "platform": "linux",
                "architecture": "x64",
                "format": "deb",
                "filename": fallback_file.name,
                "url": f"/downloads/{fallback_file.name}",
                "status": "available",
                "primary": False,
            },
            {
                "platform": "linux",
                "architecture": "x64",
                "format": "deb",
                "filename": primary_file.name,
                "url": f"/downloads/{primary_file.name}",
                "status": "available",
                "primary": True,
            },
        ],
    }
    manifest_path = tmp_path / "version.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    monkeypatch.setattr(downloads, "DOWNLOADS_DIR", tmp_path)
    monkeypatch.setattr(downloads, "MANIFEST_PATH", manifest_path)

    response = client.get(
        "/api/downloads/detect",
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        },
    )
    assert response.status_code == 200

    payload = response.json()
    assert payload["platform"] == "linux"
    assert payload["architecture"] == "x64"
    assert payload["recommended_download"] == f"/downloads/{primary_file.name}"
