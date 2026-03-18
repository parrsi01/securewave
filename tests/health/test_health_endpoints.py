def test_health_endpoints_available(client):
    r1 = client.get("/health")
    assert r1.status_code == 200
    assert r1.json()["status"] == "ok"

    r2 = client.get("/api/health")
    assert r2.status_code == 200
    assert r2.json()["status"] == "ok"


def test_readiness_endpoint(client):
    response = client.get("/api/ready")
    assert response.status_code in (200, 503)
    body = response.json()
    assert "status" in body


def test_version_endpoint(client):
    response = client.get("/version")
    assert response.status_code == 200
    body = response.json()
    assert "version" in body
