def test_auth_me(client, auth_headers):
    response = client.get("/api/auth/me", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "test@example.com"


def test_vpn_demo_flow(client, auth_headers):
    connect = client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)
    assert connect.status_code == 200
    connect_data = connect.json()
    assert connect_data["status"] in {"CONNECTING", "CONNECTED"}

    for _ in range(5):
        status = client.get("/api/vpn/status", headers=auth_headers)
        assert status.status_code == 200
        status_data = status.json()
        if status_data["status"] == "CONNECTED":
            break
        time.sleep(0.3)
    assert status_data["status"] == "CONNECTED"

    config = client.get("/api/vpn/config", headers=auth_headers)
    assert config.status_code == 200
    assert "config" in config.json()

    disconnect = client.post("/api/vpn/disconnect", json={"reason": "test"}, headers=auth_headers)
    assert disconnect.status_code == 200
import time
