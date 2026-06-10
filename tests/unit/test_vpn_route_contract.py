from pathlib import Path


def test_rate_limited_profile_route_accepts_request_argument():
    source = Path("routes/vpn.py").read_text(encoding="utf-8")
    profile_route = source.split('@router.post("/profile"', 1)[1].split('"""', 1)[0]

    assert '@rate_limit("30/minute")' in profile_route
    assert "request: Request" in profile_route
