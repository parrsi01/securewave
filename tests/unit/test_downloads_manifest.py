from pathlib import Path

import pytest

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


def test_linux_portable_manifest_keeps_runtime_truthful():
    entries = downloads._build_download_entries()
    by_name = {entry.filename: entry for entry in entries}

    x64_tar = by_name["securewave-linux-x64.tar.gz"]
    arm64_zip = by_name["securewave-app-linux-arm64.zip"]

    assert x64_tar.platform == "linux"
    assert x64_tar.architecture == "x64"
    assert x64_tar.status == "coming_soon"
    assert x64_tar.url == "#"
    assert x64_tar.size_bytes is None
    assert x64_tar.size_display is None
    assert "true x86_64 artifact" in x64_tar.notes
    assert "UI-only" in x64_tar.notes

    assert arm64_zip.platform == "linux"
    assert arm64_zip.architecture == "arm64"
    assert arm64_zip.status == "available"
    assert "Portable Linux ARM64 UI package" in arm64_zip.notes
    assert "privileged helper" in arm64_zip.notes


@pytest.mark.asyncio
async def test_linux_x64_detection_does_not_recommend_arm64_portable_zip():
    request = type(
        "Request",
        (),
        {"headers": {"user-agent": "Mozilla/5.0 (X11; Linux x86_64)"}},
    )()

    response = await downloads.detect_user_platform(request)
    detected = downloads.detect_platform(request.headers["user-agent"])

    assert detected == {"platform": "linux", "architecture": "x64"}
    assert response.recommended_download is None

    entries = [
        entry for entry in downloads._build_download_entries()
        if entry.platform == detected["platform"]
        and entry.status == "available"
        and entry.url
        and entry.url != "#"
    ]
    exact = next(
        (entry for entry in entries
         if entry.architecture == detected["architecture"]),
        None,
    )
    universal = next(
        (entry for entry in entries if entry.architecture == "universal"),
        None,
    )

    assert exact is None
    assert universal is None


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
