from pathlib import Path

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


def test_apple_review_page_and_handoff_docs_are_public():
    apple_page = (ROOT / "static/apple-review.html").read_text()
    downloads_page = (ROOT / "static/download.html").read_text()
    manifest = (ROOT / "static/downloads/manifest.json").read_text()
    handoff = (ROOT / "docs/APPLE_REVIEW_HANDOFF.md").read_text()
    macos_script = (ROOT / "securewave_app/scripts/package_macos_ui_demo.sh").read_text()
    apple_workflow = (ROOT / ".github/workflows/apple-release.yml").read_text()

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
