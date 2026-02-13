from datetime import datetime

from models.vpn_server import VPNServer


def _seed_server(
    db,
    *,
    server_id: str = "hel1-01",
    endpoint: str = "198.51.100.10:51820",
    allowed_ips: str = "0.0.0.0/0, ::/0",
):
    server = VPNServer(
        server_id=server_id,
        location="Helsinki",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        region="Europe",
        hcloud_location="hel1",
        public_ip=endpoint.split(":")[0],
        endpoint=endpoint,
        wg_public_key="dGVzdC1zZXJ2ZXIta2V5LXByb2ZpbGUtMDEyMzQ1Njc4OTAxMg==",
        wg_private_key_encrypted="encrypted-private-key",
        allowed_ips=allowed_ips,
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        performance_score=99.0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_profile_generation_returns_valid_wireguard_config(client, auth_headers, db):
    server = _seed_server(db)
    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "Work Laptop",
            "device_type": "linux",
            "server_id": server.server_id,
            "protocol": "wireguard",
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    config = data["wireguard_config"]

    assert "[Interface]" in config
    assert "[Peer]" in config
    assert f"Endpoint = {server.endpoint}" in config
    assert f"AllowedIPs = {server.allowed_ips}" in config
    assert data["server_id"] == server.server_id

    issued = datetime.fromisoformat(data["issued_at"])
    expires = datetime.fromisoformat(data["expires_at"])
    assert issued.tzinfo is not None
    assert expires.tzinfo is not None
    assert expires > issued


def test_servers_endpoint_rejects_invalid_region(client, auth_headers, db):
    _seed_server(db)
    response = client.get(
        "/api/vpn/servers",
        headers=auth_headers,
        params={"region": "<script>alert(1)</script>"},
    )
    assert response.status_code == 400
    payload = response.json()
    assert payload["error"]["code"] == "invalid_region"


def test_profile_error_contract_documented_in_openapi(client):
    response = client.get("/api/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    profile_post = schema["paths"]["/api/vpn/profile"]["post"]
    assert "400" in profile_post["responses"]
    error_schema_ref = (
        profile_post["responses"]["400"]["content"]["application/json"]["schema"]["$ref"]
    )
    assert error_schema_ref.endswith("/ApiErrorResponse")
