import json
import re
from pathlib import Path

from release_metadata import DEFAULT_APP_VERSION


ROOT = Path(__file__).resolve().parents[2]
STATIC = ROOT / "static"


def test_private_routing_palette_and_typography_are_locked():
    css = (STATIC / "css/web_ui_v1.css").read_text(encoding="utf-8")
    required_tokens = {
        "--bg": "#03060d",
        "--bg2": "#060c18",
        "--surf": "#080f20",
        "--text": "#d0e8ff",
        "--accent": "#00b4ff",
        "--accent2": "#0066cc",
    }

    for token, color in required_tokens.items():
        assert re.search(
            rf"{re.escape(token)}\s*:\s*{re.escape(color)}\s*;",
            css,
            flags=re.IGNORECASE,
        ), f"Website design token changed: {token} must remain {color}"

    assert "'Space Grotesk'" in css
    assert "'JetBrains Mono'" in css


def test_purple_replacement_theme_cannot_return():
    public_sources = [
        *STATIC.glob("*.html"),
        *STATIC.glob("css/*.css"),
        *STATIC.glob("img/*.svg"),
        *STATIC.glob("js/*.js"),
        STATIC / "favicon.svg",
    ]
    combined = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in public_sources
        if path.is_file()
    ).lower()

    for forbidden in ("#8b5cf6", "#c084fc", "#f472b6", "purple-on-black"):
        assert forbidden not in combined, f"Former purple theme returned: {forbidden}"


def test_canonical_homepage_and_live_version_display_are_preserved():
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    site_js = (STATIC / "js/site.js").read_text(encoding="utf-8")

    assert 'class="page-home"' in index
    assert 'id="netviz"' in index
    assert "Private routing without a" in index
    assert "1</span><span class=\"l\">Release protocol" in index
    assert "OpenVPN &#183; unavailable" in index
    assert "IKEv2 for mobile continuity" not in index
    assert "3 protocol paths" not in index
    assert not (STATIC / "home.html").exists()
    assert "fetch('/version', { cache: 'no-store' })" in site_js
    assert "data-site-version" in site_js


def test_download_version_matches_the_application_release():
    pubspec = (ROOT / "securewave_app/pubspec.yaml").read_text(encoding="utf-8")
    manifest = json.loads(
        (STATIC / "downloads/manifest.json").read_text(encoding="utf-8")
    )

    assert f"version: {DEFAULT_APP_VERSION}" in pubspec
    assert manifest["version"] == DEFAULT_APP_VERSION


def test_home_aliases_and_favicon_use_canonical_assets(client):
    for route in ("/", "/home", "/home.html"):
        response = client.get(route)
        assert response.status_code == 200
        assert "Private routing without a" in response.text

    favicon = client.get("/favicon.svg")
    assert favicon.status_code == 200
    assert "<svg" in favicon.text
