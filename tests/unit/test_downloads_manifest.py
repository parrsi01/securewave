from routes import downloads


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
