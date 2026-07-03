from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from routes import downloads

ROOT = Path(__file__).resolve().parents[2]


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
    for demo in (arm64_demo, x64_demo):
        if (downloads.DOWNLOADS_DIR / demo.filename).exists():
            assert demo.status == "available"
            assert demo.url == f"/downloads/{demo.filename}"
        else:
            assert demo.status == "coming_soon"
            assert demo.url == "#"


def test_download_manifest_status_and_checksums_follow_files():
    entries = downloads._build_download_entries()

    for entry in entries:
        if not entry.filename:
            assert entry.status == "coming_soon"
            assert entry.sha256 is None
            continue

        path = downloads.DOWNLOADS_DIR / entry.filename
        if path.exists():
            assert entry.status == "available"
            assert entry.url == f"/downloads/{entry.filename}"
            assert entry.size_bytes == path.stat().st_size
            assert entry.sha256
            assert len(entry.sha256) == 64
        else:
            assert entry.status == "coming_soon"
            assert entry.url == "#"
            assert entry.sha256 is None


def test_linux_download_notes_are_production_truthful():
    entries = {
        entry.filename: entry
        for entry in downloads._build_download_entries()
        if entry.platform == "linux"
    }

    assert entries["securewave-linux-x64.deb"].supports_full_routing is True
    assert entries["securewave-linux-arm64.deb"].supports_full_routing is True
    assert "helper service" in entries["securewave-linux-x64.deb"].notes
    assert entries["securewave-linux-x64.tar.gz"].supports_full_routing is False
    assert entries["securewave-app-linux-arm64.zip"].supports_full_routing is False
    assert "only when the SecureWave .deb helper service is already installed" in entries[
        "securewave-linux-x64.tar.gz"
    ].notes


def test_linux_recommendation_prefers_full_routing_deb():
    entries = [
        downloads.DownloadEntry(
            platform="linux",
            architecture="arm64",
            filename="securewave-app-linux-arm64.zip",
            url="/downloads/securewave-app-linux-arm64.zip",
            version="test",
            status="available",
            notes="Portable UI",
            supports_full_routing=False,
        ),
        downloads.DownloadEntry(
            platform="linux",
            architecture="arm64",
            filename="securewave-linux-arm64.deb",
            url="/downloads/securewave-linux-arm64.deb",
            version="test",
            status="available",
            notes="Full routing",
            supports_full_routing=True,
        ),
    ]

    selected = downloads._select_recommended_download(
        entries, {"platform": "linux", "architecture": "arm64"}
    )

    assert selected is not None
    assert selected.filename == "securewave-linux-arm64.deb"


def test_downloads_api_recommends_linux_deb_when_available():
    app = FastAPI()
    app.include_router(downloads.router)
    client = TestClient(app)

    response = client.get(
        "/api/downloads/detect",
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux aarch64)"},
    )

    assert response.status_code == 200
    assert response.json()["recommended_download"] == "/downloads/securewave-linux-arm64.deb"


def test_linux_recommendation_does_not_claim_portable_full_routing():
    entries = [
        downloads.DownloadEntry(
            platform="linux",
            architecture="x64",
            filename="securewave-linux-x64.tar.gz",
            url="/downloads/securewave-linux-x64.tar.gz",
            version="test",
            status="available",
            notes="Portable UI",
            supports_full_routing=False,
        ),
    ]

    selected = downloads._select_recommended_download(
        entries, {"platform": "linux", "architecture": "x64"}
    )

    assert selected is None


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
    assert "first_line()" in ios_doctor
    assert "| head -n 1" not in ios_doctor
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
