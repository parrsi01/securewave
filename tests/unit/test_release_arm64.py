import json
from pathlib import Path

import pytest

from scripts import release_arm64
from scripts.cli_operation_common import fingerprint_api_base


def test_external_release_paths_cannot_be_repository_local(tmp_path: Path):
    with pytest.raises(release_arm64.Arm64ReleaseBlocked, match="outside the repository"):
        release_arm64._external_path(release_arm64.ROOT / "secret.json", "approval_file")


def test_live_api_validation_requires_the_packet_fingerprint(monkeypatch):
    api_base = "https://api.example.test/api"
    packet = {"api_base_fingerprint": fingerprint_api_base(api_base)}
    monkeypatch.setenv("SECUREWAVE_API_BASE_URL", api_base)

    assert release_arm64._validate_live_api_base(packet) == {
        "supplied": True,
        "fingerprint_matches": True,
    }

    monkeypatch.setenv("SECUREWAVE_API_BASE_URL", "http://api.example.test/api")
    with pytest.raises(release_arm64.Arm64ReleaseBlocked, match="HTTPS"):
        release_arm64._validate_live_api_base(packet)


def test_arm64_release_rejects_non_linux_hosts(monkeypatch):
    monkeypatch.setattr(release_arm64.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(release_arm64.platform, "machine", lambda: "arm64")

    with pytest.raises(release_arm64.Arm64ReleaseBlocked, match="Linux ARM64"):
        release_arm64._check_arm64_tools()


def test_manifest_match_requires_available_arm64_entry(monkeypatch, tmp_path: Path):
    artifact = tmp_path / "securewave-vpn_1.0_arm64.deb"
    artifact.write_bytes(b"package")
    manifest = tmp_path / "static/downloads/manifest.json"
    manifest.parent.mkdir(parents=True)
    manifest.write_text(
        json.dumps(
            {
                "downloads": [
                    {
                        "filename": artifact.name,
                        "platform": "linux",
                        "architecture": "arm64",
                        "status": "available",
                        "url": f"/downloads/{artifact.name}",
                        "checksum_sha256": "a" * 64,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(release_arm64, "ROOT", tmp_path)

    assert release_arm64._manifest_matches(artifact, "a" * 64) is True
    assert release_arm64._manifest_matches(artifact, "b" * 64) is False
