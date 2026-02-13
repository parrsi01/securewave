import urllib.request


def test_homepage_http_200(preview_stack):
    req = urllib.request.Request(f"{preview_stack.base_url}/", method="GET")
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - local test server
        assert resp.status == 200

