from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_public_static_pages_use_non_error_session_probe():
    site = (ROOT / "static/js/site.js").read_text(encoding="utf-8")
    auth = (ROOT / "static/js/auth.js").read_text(encoding="utf-8")

    assert "/api/auth/session" in site
    assert "/api/auth/session" in auth
    assert "fetch('/api/auth/me'" not in site
    assert "fetch('/api/auth/me'" not in auth


def test_browser_auth_handles_two_factor_verification_and_session_state():
    auth = (ROOT / "static/js/auth.js").read_text(encoding="utf-8")
    login = (ROOT / "static/login.html").read_text(encoding="utf-8")
    register = (ROOT / "static/register.html").read_text(encoding="utf-8")

    assert "data.requires_2fa" in auth
    assert "totp_code" in auth
    assert "data?.error?.message" in auth
    assert "action === 'register' && !data.access_token" in auth
    assert "hasAuthenticatedSession()" in auth
    assert "data-totp-field" in login
    assert "autocomplete=\"current-password\"" in login
    assert "autocomplete=\"new-password\"" in register


def test_staging_account_portal_is_explicit_and_same_origin_after_selection():
    auth = (ROOT / "static/js/auth.js").read_text(encoding="utf-8")
    login = (ROOT / "static/login.html").read_text(encoding="utf-8")
    nginx = (ROOT / "deploy/hetzner/staging-api.nginx").read_text(encoding="utf-8")

    assert 'href="https://staging-api.securewaveapp.com/login"' in login
    assert "data-staging-login" in login
    assert "staging-api.securewaveapp.com" in auth
    assert "root /var/www/securewave-staging;" in nginx
    assert "try_files $uri $uri.html /404.html;" in nginx
    assert "location ^~ /downloads/" in nginx
    assert "return 404;" in nginx
    assert "proxy_pass http://127.0.0.1:8080;" in nginx


def test_dashboard_uses_supported_account_routes_without_obsolete_requests():
    dashboard = (ROOT / "static/js/dashboard.js").read_text(encoding="utf-8")
    html = (ROOT / "static/dashboard.html").read_text(encoding="utf-8")

    session_index = dashboard.index("fetch('/api/auth/session'")
    details_index = dashboard.index("fetch('/api/auth/me'")
    dashboard_index = dashboard.index("fetch('/api/dashboard/info'")
    assert session_index < details_index < dashboard_index
    assert "/api/vpn/devices" not in dashboard
    assert "/api/vpn/servers" not in dashboard
    assert "temporarily unavailable" in dashboard
    assert "data-account-email" in html
    assert "data-email-verified" in html
    assert "data-two-factor" in html
    assert "data-dashboard-message" in html


def test_account_pages_offer_only_three_current_platform_choices():
    for filename in ("login.html", "register.html"):
        content = (ROOT / "static" / filename).read_text(encoding="utf-8")
        assert content.count('class="btn download-btn"') == 3
        assert "macOS soon" in content
        assert "Windows soon" in content
        assert "Linux beta" in content
        assert "Android" not in content
        assert "iOS" not in content


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


def test_restored_homepage_is_wireguard_only_and_home_route_matches():
    index = (ROOT / "static/index.html").read_text(encoding="utf-8")
    home = (ROOT / "static/home.html").read_text(encoding="utf-8")

    assert home == index
    assert "WireGuard-only transport" in index
    assert "WireGuard protocol" in index
    assert "OpenVPN" not in index
    assert "IKEv2" not in index
    assert "3 protocol paths" not in index


def test_public_pages_do_not_link_to_removed_home_download_anchor():
    for page in (ROOT / "static").glob("*.html"):
        content = page.read_text(encoding="utf-8")
        assert 'href="/#download"' not in content, page


def test_download_page_keeps_three_platform_release_truth():
    download = (ROOT / "static/download.html").read_text(encoding="utf-8")
    downloads_js = (ROOT / "static/js/downloads.js").read_text(encoding="utf-8")

    assert "WireGuard-only Linux ARM64 beta is available" in download
    assert "macOS and Windows builds are coming soon" in download
    assert "Only the verified Linux ARM64 beta is downloadable today" in download
    assert "Mac/Xcode handoff kit is available" not in download
    assert downloads_js.index("fetch('/static/downloads/manifest.json'") < downloads_js.index(
        "fetch('/api/downloads')"
    )
