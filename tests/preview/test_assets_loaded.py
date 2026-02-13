import re
import urllib.request


def _get_text(url: str) -> str:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - local test server
        assert resp.status == 200
        return resp.read().decode("utf-8", errors="replace")


def _head_ok(url: str) -> None:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - local test server
        assert resp.status == 200


def test_assets_load_css_and_js(preview_stack):
    html = _get_text(f"{preview_stack.base_url}/")

    # Prefer explicit known assets; fall back to parsing HTML references.
    candidates = ["/css/web_ui_v1.css", "/js/site.js", "/img/logo.svg"]

    # Extract a couple of <link href="..."> and <script src="..."> to validate the page bundle.
    for href in re.findall(r'href="([^"]+)"', html):
        if href.startswith(("/css/", "/js/")):
            candidates.append(href)
    for src in re.findall(r'src="([^"]+)"', html):
        if src.startswith(("/css/", "/js/")):
            candidates.append(src)

    checked = 0
    seen = set()
    for path in candidates:
        if not path.startswith("/"):
            continue
        if path in seen:
            continue
        seen.add(path)
        _head_ok(f"{preview_stack.base_url}{path}")
        checked += 1
        if checked >= 3:
            break

    assert checked >= 3
