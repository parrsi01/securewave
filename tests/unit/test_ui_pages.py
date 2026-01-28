from pathlib import Path


STATIC_DIR = Path(__file__).resolve().parents[2] / "static"


def _read_page(name: str) -> str:
    return (STATIC_DIR / name).read_text(encoding="utf-8")


def test_home_trust_copy():
    html = _read_page("home.html")
    assert "The SecureWave app establishes the VPN tunnel on your device." in html
    assert "This website manages your account and device configuration." in html


def test_legal_placeholders_present():
    privacy = _read_page("privacy.html")
    terms = _read_page("terms.html")
    assert "Placeholder policy for development." in privacy
    assert "Placeholder terms for development." in terms


def test_no_exaggerated_claims_in_static_pages():
    banned = ("anonymous", "untraceable", "military-grade")
    for page in STATIC_DIR.glob("*.html"):
        content = page.read_text(encoding="utf-8").lower()
        for word in banned:
            assert word not in content, f"{word} found in {page.name}"
