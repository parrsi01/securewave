import os
import subprocess
from pathlib import Path


def test_key_web_pages_http_200(client):
    # Static pages should be reachable (web center is read-only; VPN runs in the app).
    paths = [
        "/",
        "/home",
        "/subscription",
        "/download",
        "/privacy",
        "/terms",
        "/data_retention",
        "/acceptable_use",
        "/login",
        "/register",
        "/dashboard",
        "/vpn",
        "/billing",
        "/diagnostics",
        "/settings",
    ]

    for path in paths:
        resp = client.get(path)
        assert resp.status_code == 200, f"{path} -> {resp.status_code}"


def test_404_page_is_custom_html(client):
    resp = client.get("/definitely-not-a-real-route")
    assert resp.status_code == 404
    body = resp.text
    assert "Page not found" in body
    assert "SecureWave" in body


def test_footer_contains_legal_links():
    static_dir = Path(__file__).resolve().parents[2] / "static"
    required_links = [
        'href="/privacy"',
        'href="/terms"',
        'href="/data_retention"',
        'href="/acceptable_use"',
    ]

    # Not every page has a footer (e.g., 404); focus on primary pages.
    pages = [
        "index.html",
        "home.html",
        "subscription.html",
        "download.html",
        "privacy.html",
        "terms.html",
        "data_retention.html",
        "acceptable_use.html",
        "dashboard.html",
        "billing.html",
        "vpn.html",
        "diagnostics.html",
        "settings.html",
    ]

    for page in pages:
        html = (static_dir / page).read_text(encoding="utf-8")
        for link in required_links:
            assert link in html, f"{page} missing {link}"


def test_first_party_js_syntax_and_no_console_error():
    # This is a best-effort guardrail to avoid shipping obvious JS issues without
    # pulling in a full browser automation dependency in CI.
    node = os.getenv("NODE_BIN") or "node"
    try:
        subprocess.run([node, "--version"], check=True, capture_output=True, text=True)  # nosec B603
    except Exception:
        return  # Skip if node isn't available

    static_js = Path(__file__).resolve().parents[2] / "static" / "js"
    js_files = [
        static_js / "site.js",
        static_js / "auth.js",
        static_js / "dashboard.js",
        static_js / "billing_center.js",
        static_js / "device_center.js",
        static_js / "chat_assistant.js",
    ]

    for path in js_files:
        assert path.exists(), f"Missing JS file: {path}"
        # Syntax check only (no execution).
        subprocess.run([node, "--check", str(path)], check=True, capture_output=True, text=True)  # nosec B603

        text = path.read_text(encoding="utf-8", errors="replace")
        assert "console.error" not in text, f"console.error present in {path.name}"

