import hashlib
import json
from pathlib import Path

from routes import downloads

ROOT = Path(__file__).resolve().parents[2]


def _manifest_row(
    filename: str,
    *,
    status: str = "available",
    platform: str = "linux",
    architecture: str = "x64",
    url: str | None = None,
    checksum_sha256: str | None = None,
) -> dict:
    row = {
        "platform": platform,
        "architecture": architecture,
        "filename": filename,
        "url": url if url is not None else f"/downloads/{filename}",
        "status": status,
        "notes": "Focused download manifest test artifact.",
    }
    if checksum_sha256 is not None:
        row["checksum_sha256"] = checksum_sha256
    return row


def _configure_downloads(monkeypatch, tmp_path, rows) -> Path:
    downloads_dir = tmp_path / "downloads"
    downloads_dir.mkdir()
    manifest_path = downloads_dir / "manifest.json"
    manifest_path.write_text(json.dumps({"version": "test", "downloads": rows}))
    monkeypatch.setattr(downloads, "DOWNLOADS_DIR", downloads_dir)
    monkeypatch.setattr(downloads, "DOWNLOAD_MANIFEST_PATH", manifest_path)
    return downloads_dir


def test_download_manifest_exposes_apple_handoff_zip():
    entries = downloads._build_download_entries()
    handoff = next(
        entry for entry in entries
        if entry.filename == "securewave-apple-release-handoff.zip"
    )

    assert handoff.platform == "macos"
    assert handoff.architecture == "universal"
    assert handoff.status == "available"
    assert handoff.url == "/downloads/securewave-apple-release-handoff.zip"


def test_download_manifest_exposes_macos_demo_slots():
    entries = downloads._build_download_entries()
    by_name = {entry.filename: entry for entry in entries}

    arm64_demo = by_name["securewave-macos-arm64-ui-demo.zip"]
    x64_demo = by_name["securewave-macos-x64-ui-demo.zip"]

    assert arm64_demo.platform == "macos"
    assert arm64_demo.architecture == "arm64"
    assert x64_demo.platform == "macos"
    assert x64_demo.architecture == "x64"
    if (downloads.DOWNLOADS_DIR / arm64_demo.filename).exists():
        assert arm64_demo.status == "available"
        assert arm64_demo.url == f"/downloads/{arm64_demo.filename}"
    else:
        assert arm64_demo.status == "coming_soon"
        assert arm64_demo.url == "#"

    # Presence alone must not publish an artifact the manifest still withholds.
    assert x64_demo.status == "coming_soon"
    assert x64_demo.url == "#"


def test_linux_x64_deb_is_withheld_build_evidence_not_release_download():
    entries = downloads._build_download_entries()
    linux_x64_deb = next(
        entry for entry in entries
        if entry.filename == "securewave-linux-x64.deb"
    )

    assert linux_x64_deb.platform == "linux"
    assert linux_x64_deb.architecture == "x64"
    assert linux_x64_deb.status == "coming_soon"
    assert linux_x64_deb.url == "#"
    assert linux_x64_deb.evidence_url == (
        "https://github.com/parrsi01/securewave/actions/runs/29348489573"
    )
    assert linux_x64_deb.checksum_sha256 == (
        "4d1733bd5a9e0d23806543fe36956feb7766e7ea101342270ea9f09d0f1aa80e"
    )
    assert "clean x86_64 VM install" in (linux_x64_deb.notes or "")


def test_apple_review_page_and_handoff_docs_are_public():
    apple_page = (ROOT / "static/apple-review.html").read_text()
    downloads_page = (ROOT / "static/download.html").read_text()
    manifest = (ROOT / "static/downloads/manifest.json").read_text()
    handoff = (ROOT / "docs/APPLE_REVIEW_HANDOFF.md").read_text()
    macos_script = (ROOT / "securewave_app/scripts/package_macos_ui_demo.sh").read_text()
    ios_doctor = (ROOT / "securewave_app/scripts/doctor_flutter_ios.sh").read_text()
    apple_workflow = (ROOT / ".github/workflows/apple-release.yml").read_text()
    apple_release = (ROOT / "docs/APPLE_RELEASE.md").read_text()

    assert "Packet Tunnel Provider" in apple_page
    assert "Hotspot Helper" in apple_page
    assert "/privacy.html" in apple_page
    assert "/contact.html" in apple_page
    assert "/apple-review.html" in downloads_page
    assert "securewave-apple-release-handoff.zip" in manifest
    assert "securewave-macos-arm64-ui-demo.zip" in manifest
    assert "package_macos_ui_demo.sh" in handoff
    assert "com.securewave.vpn.PacketTunnel" in handoff
    assert "vpn_not_configured" in macos_script
    assert "publish_macos_demo" in apple_workflow
    assert "macOS UI Demo Package" in apple_workflow
    assert "static/downloads/securewave-macos-*-ui-demo.zip" in apple_workflow
    assert "--no-enable-swift-package-manager" in apple_workflow
    assert "scripts/prepare_flutter_env.sh" in apple_workflow
    assert "Collect unsigned iOS app artifact" in apple_workflow
    assert "find securewave_app/build/ios -type d -name '*.app'" in apple_workflow
    assert "apple-artifacts/ios-unsigned/securewave-ios-unsigned.zip" in apple_workflow
    assert "SECUREWAVE_IOS_RELEASE_SIGNING" in ios_doctor
    assert "Apple Distribution signing identity available" in ios_doctor
    assert "com.securewave.vpn.PacketTunnel" in ios_doctor
    assert "SECUREWAVE_IOS_RELEASE_SIGNING=1" in apple_release


def test_macos_detection_can_recommend_universal_handoff():
    detected = downloads.detect_platform(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15",
    )

    assert detected == {"platform": "macos", "architecture": "x64"}
    recommended = None
    for item in downloads._load_download_manifest():
        if item["platform"] == detected["platform"] and item["architecture"] in (
            detected["architecture"],
            "universal",
        ):
            recommended = item["url"]
            break

    assert recommended == "/downloads/securewave-apple-release-handoff.zip"


def test_coming_soon_status_is_not_promoted_or_served_when_file_exists(
    monkeypatch,
    tmp_path,
    client,
):
    rows = [_manifest_row("withheld.bin", status="coming_soon")]
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, rows)
    (downloads_dir / "withheld.bin").write_bytes(b"not released")

    [entry] = downloads._build_download_entries()

    assert entry.status == "coming_soon"
    assert entry.url == "#"
    assert entry.size_bytes is None
    assert client.get("/api/downloads/file/withheld.bin").status_code == 404


def test_available_local_file_requires_matching_checksum(monkeypatch, tmp_path, client):
    content = b"trusted release artifact"
    checksum = hashlib.sha256(content).hexdigest()
    rows = [_manifest_row("trusted.bin", checksum_sha256=checksum)]
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, rows)
    (downloads_dir / "trusted.bin").write_bytes(content)

    [entry] = downloads._build_download_entries()
    assert entry.status == "available"
    assert entry.checksum_sha256 == checksum

    response = client.get("/api/downloads/file/trusted.bin")
    assert response.status_code == 200
    assert response.content == content


def test_checksum_mismatch_fails_closed_for_listing_and_serving(monkeypatch, tmp_path, client):
    rows = [_manifest_row("tampered.bin", checksum_sha256="0" * 64)]
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, rows)
    (downloads_dir / "tampered.bin").write_bytes(b"different content")

    response = client.get("/api/downloads")
    assert response.status_code == 200
    [entry] = response.json()["downloads"]
    assert entry["status"] == "coming_soon"
    assert entry["url"] == "#"
    assert entry["size_bytes"] is None

    download_response = client.get("/api/downloads/file/tampered.bin")
    assert download_response.status_code == 404


def test_malformed_manifest_rows_are_skipped_without_api_failure(monkeypatch, tmp_path, client):
    rows = [
        _manifest_row("valid.bin", status="coming_soon"),
        _manifest_row("../escape.bin"),
        {"platform": "linux"},
        {**_manifest_row("extra.bin"), "unexpected": "field"},
        {**_manifest_row("wrong-status.bin"), "status": "published"},
        _manifest_row("unsafe-url.bin", status="beta", url="javascript:alert(1)"),
        {
            **_manifest_row("unsafe-evidence.bin", status="beta", url="https://example.invalid/build"),
            "evidence_url": "http://insecure.example.invalid/evidence",
        },
    ]
    _configure_downloads(monkeypatch, tmp_path, rows)

    response = client.get("/api/downloads")

    assert response.status_code == 200
    assert [entry["filename"] for entry in response.json()["downloads"]] == ["valid.bin"]


def test_invalid_manifest_structure_uses_safe_fallback(monkeypatch, tmp_path, client):
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, [])
    manifest_path = downloads_dir / "manifest.json"
    manifest_path.write_text("{}")

    response = client.get("/api/downloads")

    assert response.status_code == 200
    entries = response.json()["downloads"]
    withheld = next(entry for entry in entries if entry["filename"] == "securewave-linux-x64.deb")
    assert withheld["status"] == "coming_soon"
    assert withheld["url"] == "#"
    assert withheld["evidence_url"] == (
        "https://github.com/parrsi01/securewave/actions/runs/29348489573"
    )


def test_unlisted_and_traversal_files_are_not_served(monkeypatch, tmp_path, client):
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, [])
    (downloads_dir / "unlisted.bin").write_bytes(b"not public")

    unlisted = client.get("/api/downloads/file/unlisted.bin")
    traversal = client.get("/api/downloads/file/%2E%2E%2Fsecret.bin")

    assert unlisted.status_code == 404
    assert traversal.status_code == 400


def test_platform_detection_never_recommends_beta_or_coming_soon(
    monkeypatch,
    tmp_path,
    client,
):
    rows = [
        _manifest_row(
            "linux-beta.deb",
            status="beta",
            url="https://example.invalid/build-evidence",
        ),
        _manifest_row("linux-withheld.tar.gz", status="coming_soon"),
    ]
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, rows)
    (downloads_dir / "linux-beta.deb").write_bytes(b"beta")
    (downloads_dir / "linux-withheld.tar.gz").write_bytes(b"withheld")

    response = client.get(
        "/api/downloads/detect",
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"},
    )

    assert response.status_code == 200
    assert response.json()["recommended_download"] is None
    assert client.get("/api/downloads/file/linux-beta.deb").status_code == 404


def test_public_download_urls_share_guarded_runtime_truth(monkeypatch, tmp_path, client):
    content = b"public artifact"
    checksum = hashlib.sha256(content).hexdigest()
    rows = [
        _manifest_row("public.bin", checksum_sha256=checksum),
        _manifest_row("withheld.bin", status="coming_soon"),
        _manifest_row(
            "beta.bin",
            status="beta",
            url="https://example.invalid/build-evidence",
        ),
    ]
    downloads_dir = _configure_downloads(monkeypatch, tmp_path, rows)
    (downloads_dir / "public.bin").write_bytes(content)
    (downloads_dir / "withheld.bin").write_bytes(b"withheld")
    (downloads_dir / "beta.bin").write_bytes(b"beta")
    (downloads_dir / "unlisted.bin").write_bytes(b"unlisted")

    runtime_manifest = client.get("/downloads/manifest.json")
    assert runtime_manifest.status_code == 200
    statuses = {item["filename"]: item["status"] for item in runtime_manifest.json()["downloads"]}
    assert statuses == {"public.bin": "available", "withheld.bin": "coming_soon", "beta.bin": "beta"}

    assert client.get("/downloads/public.bin").content == content
    assert client.get("/downloads/withheld.bin").status_code == 404
    assert client.get("/downloads/beta.bin").status_code == 404
    assert client.get("/downloads/unlisted.bin").status_code == 404
    assert client.get("/downloads/%2E%2E%2Fsecret.bin").status_code == 400
