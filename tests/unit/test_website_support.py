"""Shared support coverage and readable foreground regression contracts."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATIC = ROOT / "static"


def test_every_page_loads_support_and_current_styles():
    pages = list(STATIC.glob("*.html"))
    assert pages
    for page in pages:
        html = page.read_text()
        assert re.search(r'<script[^>]+src="/js/(site|chat_assistant)\.js\?v=20260908"', html), page.name
        assert '/css/web_ui_v1.css?v=20260908' in html, page.name
        assert 'href="/#download"' not in html, page.name


def test_support_links_resolve_to_served_files():
    source = (STATIC / "js/chat_assistant.js").read_text()
    for target in re.findall(r"/([a-z-]+\.html)", source):
        assert (STATIC / target).is_file(), target
    assert 'home.html#download' not in source
    assert 'fetch(' not in source


def test_support_panel_has_hidden_and_mobile_contracts():
    css = (STATIC / "css/web_ui_v1.css").read_text()
    assert re.search(r'\.sw-chat-panel\[hidden\]\s*\{\s*display:\s*none', css)
    assert '100dvh' in css
    assert 'safe-area-inset-bottom' in css


def test_supporting_text_contrast_on_surfaces():
    css = (STATIC / "css/web_ui_v1.css").read_text()
    def luminance(token):
        color = re.search(rf'{token}:\s*#([0-9a-f]{{6}})', css).group(1)
        values = [int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
        return sum(a * b for a, b in zip(linear, (.2126, .7152, .0722)))
    for foreground in ('--muted', '--subtle', '--text'):
        for background in ('--bg', '--bg2', '--surf'):
            assert (luminance(foreground) + .05) / (luminance(background) + .05) >= 4.5
