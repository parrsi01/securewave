import json
import urllib.request


def test_api_health_reachable_via_same_origin(preview_stack):
    # If nginx is available, preview_stack.base_url is the proxy URL. Otherwise it's direct backend.
    req = urllib.request.Request(f"{preview_stack.base_url}/api/health", method="GET")
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - local test server
        assert resp.status == 200
        payload = json.loads(resp.read().decode("utf-8"))
        # Health endpoint returns structured JSON in this project.
        assert isinstance(payload, dict)

