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


def test_active_website_brand_palette_is_navy_blue_cyan_not_purple():
    active_assets = [
        ROOT / "static/css/web_ui_v1.css",
        ROOT / "static/img/logo.svg",
        ROOT / "static/favicon.svg",
        ROOT / "assets/brand/logo.svg",
        ROOT / "assets/brand/logo-mono.svg",
        ROOT / "securewave_app/assets/securewave_logo.svg",
        ROOT / "securewave_app/web/favicon.svg",
    ]
    forbidden = (
        "purple",
        "violet",
        "indigo",
        "#8b5cf6",
        "#6d3ef0",
        "#c084fc",
        "#f472b6",
        "#a78bfa",
        "#6d28d9",
    )

    for path in active_assets:
        content = path.read_text(encoding="utf-8").lower()
        assert not any(token in content for token in forbidden), path
