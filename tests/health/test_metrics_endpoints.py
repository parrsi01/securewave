def test_prometheus_metrics_format(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    body = response.text
    assert "# HELP securewave_vpn_profiles_issued_total" in body
    assert "# TYPE securewave_system_cpu_percent gauge" in body
    assert "securewave_system_memory_percent" in body


def test_api_vpn_metrics_requires_auth(client):
    response = client.get("/api/metrics/vpn")
    assert response.status_code == 401


def test_api_vpn_metrics_payload(client, auth_headers):
    response = client.get("/api/metrics/vpn", headers=auth_headers)
    assert response.status_code == 200, response.text
    payload = response.json()
    assert "health_classification" in payload
    assert "peers" in payload
    assert "ip_pool" in payload
    assert "runtime" in payload
