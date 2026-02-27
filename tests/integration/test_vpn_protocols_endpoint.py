from models.vpn_server import VPNServer


def _create_server(
    db,
    *,
    server_id: str,
    supports_wireguard: bool = True,
    supports_openvpn: bool = False,
    supports_ikev2: bool = False,
):
    server = VPNServer(
        server_id=server_id,
        location="Frankfurt, DE",
        country="Germany",
        country_code="DE",
        city="Frankfurt",
        region="Europe",
        hcloud_location="fsn1",
        public_ip="10.10.10.10",
        endpoint="10.10.10.10:51820",
        wg_public_key="dGVzdC1wcm90b2NvbHMtc2VydmVyLXB1YmxpYy1rZXk=",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=supports_wireguard,
        supports_openvpn=supports_openvpn,
        supports_ikev2=supports_ikev2,
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST_IKEV2\n-----END CERTIFICATE-----",
        ikev2_remote_id="vpn.test.example",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_protocols_endpoint_reports_protocol_capabilities(client, auth_headers, db):
    _create_server(db, server_id="wg-only-1", supports_wireguard=True)
    _create_server(db, server_id="ovpn-1", supports_wireguard=True, supports_openvpn=True)
    _create_server(db, server_id="ikev2-1", supports_wireguard=True, supports_ikev2=True)

    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "windows"},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text

    data = response.json()
    items = {item["protocol"]: item for item in data["protocols"]}
    assert set(items.keys()) == {"wireguard", "openvpn", "ikev2"}

    assert items["wireguard"]["enabled"] is True
    assert items["openvpn"]["server_enabled"] is True
    assert items["ikev2"]["server_enabled"] is True
    assert items["openvpn"]["transports"] == ["udp", "tcp"]


def test_protocols_endpoint_rejects_invalid_device_type(client, auth_headers):
    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "playstation"},
        headers=auth_headers,
    )
    assert response.status_code == 400, response.text
    payload = response.json()
    assert payload["error"]["code"] == "invalid_device_type"
