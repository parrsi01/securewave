from models.vpn_server import VPNServer


def _seed_server(
    db,
    *,
    server_id: str,
    city: str,
    country: str,
    country_code: str,
    region: str,
    public_ip: str,
    endpoint: str,
    supports_openvpn: bool,
    supports_ikev2: bool,
    tier_restriction: str | None = None,
):
    server = VPNServer(
        server_id=server_id,
        location=city,
        country=country,
        country_code=country_code,
        city=city,
        region=region,
        hcloud_location="fsn1",
        public_ip=public_ip,
        endpoint=endpoint,
        wg_public_key=f"{server_id}-wg-public",
        wg_private_key_encrypted=f"{server_id}-wg-private",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        supports_wireguard=True,
        supports_openvpn=supports_openvpn,
        supports_ikev2=supports_ikev2,
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST_IKEV2\n-----END CERTIFICATE-----",
        ikev2_remote_id="vpn.example.test",
        tier_restriction=tier_restriction,
    )
    db.add(server)


def _seed_alignment_matrix(db) -> None:
    # 5 locations total, 3 marked premium-only.
    _seed_server(
        db,
        server_id="align-us-east",
        city="New York",
        country="United States",
        country_code="US",
        region="Americas",
        public_ip="203.0.113.11",
        endpoint="203.0.113.11:51820",
        supports_openvpn=True,
        supports_ikev2=True,
    )
    _seed_server(
        db,
        server_id="align-eu-west",
        city="London",
        country="United Kingdom",
        country_code="GB",
        region="Europe",
        public_ip="203.0.113.12",
        endpoint="203.0.113.12:51820",
        supports_openvpn=False,
        supports_ikev2=False,
    )
    _seed_server(
        db,
        server_id="align-ap-sg",
        city="Singapore",
        country="Singapore",
        country_code="SG",
        region="Asia",
        public_ip="203.0.113.13",
        endpoint="203.0.113.13:51820",
        supports_openvpn=True,
        supports_ikev2=False,
        tier_restriction="premium",
    )
    _seed_server(
        db,
        server_id="align-ap-tokyo",
        city="Tokyo",
        country="Japan",
        country_code="JP",
        region="Asia",
        public_ip="203.0.113.14",
        endpoint="203.0.113.14:51820",
        supports_openvpn=False,
        supports_ikev2=True,
        tier_restriction="premium",
    )
    _seed_server(
        db,
        server_id="align-eu-fsn",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        public_ip="203.0.113.15",
        endpoint="203.0.113.15:51820",
        supports_openvpn=True,
        supports_ikev2=True,
        tier_restriction="premium",
    )
    db.commit()


def test_premium_account_alignment_has_three_protocols_five_locations_and_premium_markers(
    client,
    auth_headers,
    db,
    test_subscription,
):
    _seed_alignment_matrix(db)

    protocols_resp = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert protocols_resp.status_code == 200
    payload = protocols_resp.json()
    items = {item["protocol"]: item for item in payload["protocols"]}
    assert set(items.keys()) == {"wireguard", "openvpn", "ikev2"}
    assert items["wireguard"]["enabled"] is True
    assert items["openvpn"]["enabled"] is True
    assert items["ikev2"]["enabled"] is True

    compat_resp = client.get(
        "/api/vpn/protocol-capabilities",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert compat_resp.status_code == 200
    assert compat_resp.json()["protocols"] == payload["protocols"]

    servers_resp = client.get("/api/vpn/servers", headers=auth_headers)
    assert servers_resp.status_code == 200
    servers = servers_resp.json()["servers"]
    assert len(servers) >= 5
    premium_marked = [
        item
        for item in servers
        if item.get("premium_only") is True
        or (item.get("tier_restriction") or "").strip().lower() == "premium"
    ]
    assert len(premium_marked) >= 3

    regions_resp = client.get("/api/vpn/regions", headers=auth_headers)
    assert regions_resp.status_code == 200
    regions = regions_resp.json()["regions"]
    assert len(regions) == len(servers)


def test_free_account_filters_premium_servers_from_catalog(client, auth_headers, db):
    _seed_alignment_matrix(db)

    servers_resp = client.get("/api/vpn/servers", headers=auth_headers)
    assert servers_resp.status_code == 200
    servers = servers_resp.json()["servers"]

    # Free users should only see unrestricted servers.
    assert all(
        (item.get("tier_restriction") in (None, "", "none"))
        and item.get("premium_only") is False
        for item in servers
    )
    assert len(servers) == 2
