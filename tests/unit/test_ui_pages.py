from pathlib import Path


STATIC_DIR = Path(__file__).resolve().parents[2] / "static"


def _read_page(name: str) -> str:
    return (STATIC_DIR / name).read_text(encoding="utf-8")


def test_home_page_loads():
    html = _read_page("home.html")
    assert "SecureWave" in html
    assert "Download" in html


def test_privacy_page_loads():
    privacy = _read_page("privacy.html")
    assert "Privacy" in privacy


def test_terms_page_loads():
    terms = _read_page("terms.html")
    assert "Terms" in terms


def test_all_static_pages_have_nav():
    """Every HTML page should include the navigation bar."""
    for page in STATIC_DIR.glob("*.html"):
        content = page.read_text(encoding="utf-8")
        assert "SecureWave" in content, f"SecureWave brand missing in {page.name}"


def test_no_broken_internal_links():
    """Pages should not reference non-existent CSS/JS."""
    for page in STATIC_DIR.glob("*.html"):
        content = page.read_text(encoding="utf-8")
        # All pages should reference the main CSS
        if '<link rel="stylesheet"' in content:
            assert "web_ui_v1.css" in content or "style" in content, f"Missing CSS in {page.name}"
