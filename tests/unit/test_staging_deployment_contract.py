from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
COMPOSE = REPO_ROOT / "deploy" / "hetzner" / "staging-compose.yaml"
NGINX = REPO_ROOT / "deploy" / "hetzner" / "staging-api.nginx"


def test_staging_compose_is_fail_closed_and_loopback_only() -> None:
    text = COMPOSE.read_text(encoding="utf-8")

    assert "ENVIRONMENT: staging" in text
    assert "ENVIRONMENT: production" not in text
    assert 'WG_MOCK_MODE: "false"' in text
    assert 'DEMO_MODE: "false"' in text
    assert '"127.0.0.1:8080:8080"' in text
    assert "openvpn" not in text.lower()
    assert "ikev2" not in text.lower()
    assert "strongswan" not in text.lower()


def test_staging_nginx_exposes_only_documented_api_proxy() -> None:
    text = NGINX.read_text(encoding="utf-8")

    assert text.count("proxy_pass") == 1
    assert "location /api/" in text
    assert "proxy_pass http://127.0.0.1:8080;" in text
    assert "location / {" in text
    assert "return 404;" in text
    assert "staging-api.securewaveapp.com" in text
