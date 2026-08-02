from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_public_static_pages_use_non_error_session_probe():
    site = (ROOT / "static/js/site.js").read_text(encoding="utf-8")
    auth = (ROOT / "static/js/auth.js").read_text(encoding="utf-8")

    assert "/api/auth/session" in site
    assert "/api/auth/session" in auth
    assert "fetch('/api/auth/me'" not in site
    assert "fetch('/api/auth/me'" not in auth


def test_contact_form_posts_to_existing_submit_endpoint():
    contact = (ROOT / "static/js/contact.js").read_text(encoding="utf-8")

    assert "fetch('/api/contact/submit'" in contact
    assert "fetch('/api/contact'," not in contact


def test_device_center_escapes_backend_values_before_html_insertion():
    device_center = (ROOT / "static/js/device_center.js").read_text(encoding="utf-8")

    assert "function escapeHtml(value)" in device_center
    assert "escapeHtml(label)" in device_center
    assert "escapeHtml(name)" in device_center
    assert "escapeHtml(type)" in device_center
    assert "escapeHtml(d.ip_address || '')" in device_center


def test_public_assistant_has_runtime_styles_and_current_download_route():
    css = (ROOT / "static/css/web_ui_v1.css").read_text(encoding="utf-8")
    site = (ROOT / "static/js/site.js").read_text(encoding="utf-8")
    assistant = (ROOT / "static/js/chat_assistant.js").read_text(encoding="utf-8")

    for selector in (
        ".sw-chat-fab",
        ".sw-chat-panel",
        ".sw-chat-panel.open",
        ".sw-chat-close",
        ".sw-chat-messages",
        ".sw-chat-quick",
        ".sw-chat-footer",
    ):
        assert selector in css

    assert "/js/chat_assistant.js?v=" in site
    assert assistant.count("go:/download.html") == 3
    assert "/home.html" not in assistant
    assert "go:/#download" not in assistant
