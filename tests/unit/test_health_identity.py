"""Pin the health endpoints' service identity.

The health payload is the only in-band identity signal the deployed API
exposes, so release verification compares it against this contract. The
legacy label "securewave-vpn-demo" (from the 2026-01 demo app) must not
return: it misreports a production build as a demo service.
"""


def test_health_reports_service_identity(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "securewave-vpn"}


def test_api_health_reports_service_identity(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "securewave-vpn"}
