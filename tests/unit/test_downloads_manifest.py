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


def test_apple_review_page_and_handoff_docs_are_public():
    apple_page = (ROOT / "static/apple-review.html").read_text()
    downloads_page = (ROOT / "static/download.html").read_text()
    manifest = (ROOT / "static/downloads/manifest.json").read_text()
    handoff = (ROOT / "docs/APPLE_REVIEW_HANDOFF.md").read_text()

    assert "Packet Tunnel Provider" in apple_page
    assert "Hotspot Helper" in apple_page
    assert "/privacy.html" in apple_page
    assert "/contact.html" in apple_page
    assert "/apple-review.html" in downloads_page
    assert "securewave-apple-release-handoff.zip" in manifest
    assert "com.securewave.vpn.PacketTunnel" in handoff


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
