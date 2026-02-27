import pytest

from models.vpn_server import VPNServer


def _set_health_override(client, auth_headers, *, clear: bool = False, overrides: list[dict] | None = None):
    payload = {
        "clear": clear,
        "overrides": overrides or [],
    }
    response = client.post("/api/vpn/dev/region-health", json=payload, headers=auth_headers)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.fixture(autouse=True)
def _reset_region_health_simulator(client, auth_headers):
    _set_health_override(client, auth_headers, clear=True)
    yield
    _set_health_override(client, auth_headers, clear=True)


def _create_server(
    db,
    *,
    server_id: str,
    region: str = "Europe",
    region_group: str | None = None,
    is_primary_region: bool = False,
    priority_weight: int = 100,
    city: str = "Frankfurt",
    country: str = "Germany",
    country_code: str = "DE",
    supports_wireguard: bool = True,
    supports_openvpn: bool = False,
    supports_ikev2: bool = False,
    health_status: str = "healthy",
    openvpn_ca_cert_pem: str = "-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
    ikev2_ca_cert_pem: str = "-----BEGIN CERTIFICATE-----\nTEST_IKEV2\n-----END CERTIFICATE-----",
    ikev2_remote_id: str = "vpn.test.example",
):
    server = VPNServer(
        server_id=server_id,
        location=f"{city}, {country_code}",
        country=country,
        country_code=country_code,
        city=city,
        region=region,
        region_group=region_group,
        is_primary_region=is_primary_region,
        priority_weight=priority_weight,
        hcloud_location="fsn1",
        public_ip="10.10.10.10",
        endpoint="10.10.10.10:51820",
        wg_public_key="dGVzdC1wcm90b2NvbHMtc2VydmVyLXB1YmxpYy1rZXk=",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status=health_status,
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=supports_wireguard,
        supports_openvpn=supports_openvpn,
        supports_ikev2=supports_ikev2,
        openvpn_ca_cert_pem=openvpn_ca_cert_pem,
        ikev2_ca_cert_pem=ikev2_ca_cert_pem,
        ikev2_remote_id=ikev2_remote_id,
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
    assert items["wireguard"]["health_status"] == "healthy"
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


def test_protocols_endpoint_marks_misconfigured_openvpn(client, auth_headers, db):
    _create_server(
        db,
        server_id="ovpn-misconfigured",
        supports_wireguard=True,
        supports_openvpn=True,
        openvpn_ca_cert_pem="",
    )

    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["openvpn"]["enabled"] is False
    assert items["openvpn"]["server_enabled"] is False
    assert items["openvpn"]["reason"] == "unavailable_region"
    assert items["openvpn"]["health_status"] == "unavailable"
    assert items["openvpn"]["health_reason"] == "unavailable_region"


def test_protocols_endpoint_disables_ikev2_linux_when_auth_mode_mismatch(
    client,
    auth_headers,
    db,
    monkeypatch,
):
    monkeypatch.setenv("SECUREWAVE_IKEV2_AUTH_MODE", "eap-tls")
    _create_server(
        db,
        server_id="ikev2-eaptls",
        supports_wireguard=True,
        supports_ikev2=True,
    )

    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["ikev2"]["server_enabled"] is True
    assert items["ikev2"]["enabled"] is False
    assert items["ikev2"]["reason"] == "ikev2_auth_mode_mismatch_linux"


def test_protocols_endpoint_keeps_degraded_protocol_enabled(client, auth_headers, db):
    _create_server(
        db,
        server_id="ovpn-degraded",
        supports_wireguard=True,
        supports_openvpn=True,
        health_status="degraded",
    )
    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["openvpn"]["enabled"] is True
    assert items["openvpn"]["server_enabled"] is True
    assert items["openvpn"]["health_status"] == "healthy"
    assert items["openvpn"]["health_reason"] is None


def test_protocols_endpoint_disables_openvpn_and_ikev2_when_runtime_material_missing(
    client,
    auth_headers,
    db,
    monkeypatch,
):
    monkeypatch.setenv("SECUREWAVE_TEST_ENFORCE_RUNTIME_CHECKS", "true")
    monkeypatch.setattr("routes.vpn._protocol_material_ready", lambda protocol: protocol == "wireguard")
    monkeypatch.setattr("routes.vpn._protocol_health_ready", lambda protocol: True)
    _create_server(db, server_id="ovpn-checked", supports_wireguard=True, supports_openvpn=True)
    _create_server(db, server_id="ikev2-checked", supports_wireguard=True, supports_ikev2=True)

    response = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["openvpn"]["enabled"] is False
    assert items["openvpn"]["reason"] == "unavailable_region"
    assert items["ikev2"]["enabled"] is False
    assert items["ikev2"]["reason"] == "unavailable_region"


def test_protocol_health_endpoint_returns_protocol_region_matrix(client, auth_headers, db):
    _create_server(
        db,
        server_id="ovpn-eu-healthy",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        supports_wireguard=True,
        supports_openvpn=True,
        health_status="healthy",
    )
    _create_server(
        db,
        server_id="ovpn-us-misconfigured",
        city="Ashburn",
        country="United States",
        country_code="US",
        region="Americas",
        supports_wireguard=True,
        supports_openvpn=True,
        health_status="healthy",
        openvpn_ca_cert_pem="",
    )
    response = client.get("/api/vpn/protocol-health", headers=auth_headers)
    assert response.status_code == 200, response.text
    payload = response.json()

    protocol_rows = {item["protocol"]: item for item in payload["protocols"]}
    assert "openvpn" in protocol_rows
    openvpn = protocol_rows["openvpn"]

    assert openvpn["status"] == "healthy"
    assert openvpn["available_servers"] >= 1
    region_rows = {item["region"]: item for item in openvpn["regions"]}
    assert "Europe" in region_rows
    assert "Americas" in region_rows
    assert region_rows["Europe"]["status"] == "healthy"
    assert region_rows["Americas"]["status"] == "unavailable"
    assert region_rows["Americas"]["reason"] == "unavailable_region"


def test_protocols_endpoint_returns_no_servers_available_when_all_regions_down(client, auth_headers, db):
    _create_server(db, server_id="down-1", supports_wireguard=True, supports_openvpn=True, supports_ikev2=True)
    _create_server(db, server_id="down-2", supports_wireguard=True, supports_openvpn=True, supports_ikev2=True)

    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "down-1", "status": "down", "reason_code": "host_unreachable"},
            {"server_id": "down-2", "status": "down", "reason_code": "timeout"},
        ],
    )

    response = client.get("/api/vpn/protocols", params={"device_type": "windows"}, headers=auth_headers)
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["wireguard"]["enabled"] is False
    assert items["openvpn"]["enabled"] is False
    assert items["ikev2"]["enabled"] is False
    assert items["wireguard"]["server_enabled"] is False
    assert items["openvpn"]["server_enabled"] is False
    assert items["ikev2"]["server_enabled"] is False
    assert items["wireguard"]["reason"] == "no_servers_available"
    assert items["openvpn"]["reason"] == "no_servers_available"
    assert items["ikev2"]["reason"] == "no_servers_available"


def test_protocols_endpoint_returns_wg_only_when_single_up_region_supports_wg(client, auth_headers, db):
    _create_server(
        db,
        server_id="wg-up",
        supports_wireguard=True,
        supports_openvpn=False,
        supports_ikev2=False,
    )
    _create_server(
        db,
        server_id="ovpn-down",
        supports_wireguard=False,
        supports_openvpn=True,
        supports_ikev2=True,
    )

    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "wg-up", "status": "up", "reason_code": "ssh_reachable"},
            {"server_id": "ovpn-down", "status": "down", "reason_code": "host_unreachable"},
        ],
    )

    response = client.get("/api/vpn/protocols", params={"device_type": "windows"}, headers=auth_headers)
    assert response.status_code == 200, response.text
    payload = response.json()
    items = {item["protocol"]: item for item in payload["protocols"]}

    assert items["wireguard"]["enabled"] is True
    assert items["wireguard"]["server_enabled"] is True
    assert items["openvpn"]["enabled"] is False
    assert items["ikev2"]["enabled"] is False
    assert items["openvpn"]["reason"] == "region_down"
    assert items["ikev2"]["reason"] == "region_down"


def test_regions_endpoint_exposes_region_health_fields(client, auth_headers, db):
    _create_server(db, server_id="region-health-1", supports_wireguard=True)
    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "region-health-1", "status": "down", "reason_code": "listener_down"},
        ],
    )
    response = client.get("/api/vpn/regions", headers=auth_headers)
    assert response.status_code == 200, response.text
    payload = response.json()
    row = next(item for item in payload["regions"] if item["server_id"] == "region-health-1")
    assert row["region_health_status"] == "down"
    assert row["region_health_reason_code"] == "listener_down"
    assert isinstance(row.get("region_health_last_checked_at"), str)


def test_resolve_region_uses_geo_primary_failover_when_preferred_region_is_down(client, auth_headers, db):
    _create_server(
        db,
        server_id="na-pref-down",
        city="Miami",
        country="United States",
        country_code="US",
        region="Americas",
        region_group="north_america",
        is_primary_region=False,
        priority_weight=5,
        supports_wireguard=True,
    )
    _create_server(
        db,
        server_id="na-primary-up",
        city="Ashburn",
        country="United States",
        country_code="US",
        region="Americas",
        region_group="north_america",
        is_primary_region=True,
        priority_weight=20,
        supports_wireguard=True,
    )
    _create_server(
        db,
        server_id="eu-low-weight-up",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        region_group="europe",
        is_primary_region=True,
        priority_weight=1,
        supports_wireguard=True,
    )

    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "na-pref-down", "status": "down", "reason_code": "host_unreachable"},
            {"server_id": "na-primary-up", "status": "up", "reason_code": "listener_up"},
            {"server_id": "eu-low-weight-up", "status": "up", "reason_code": "listener_up"},
        ],
    )

    response = client.get(
        "/api/vpn/resolve-region",
        params={
            "protocol": "wireguard",
            "device_type": "linux",
            "preferred_region": "na-pref-down",
        },
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["selected_region_id"] == "na-primary-up"
    assert payload["reason"] == "failover_primary_down"
    assert payload["protocol"] == "wireguard"


def test_resolve_region_returns_no_servers_available_when_all_regions_down(client, auth_headers, db):
    _create_server(db, server_id="resolve-down-1", supports_wireguard=True)
    _create_server(db, server_id="resolve-down-2", supports_wireguard=True)
    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "resolve-down-1", "status": "down", "reason_code": "timeout"},
            {"server_id": "resolve-down-2", "status": "down", "reason_code": "host_unreachable"},
        ],
    )

    response = client.get(
        "/api/vpn/resolve-region",
        params={"protocol": "wireguard", "device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 503, response.text
    payload = response.json()
    assert payload["error"]["code"] == "no_servers_available"


def test_resolve_region_prefers_north_america_for_barbados_ip(client, auth_headers, db, monkeypatch):
    monkeypatch.setenv(
        "SECUREWAVE_LIGHT_GEOIP_CIDR_MAP",
        '{"203.0.113.0/24":"BB"}',
    )
    _create_server(
        db,
        server_id="na-primary",
        city="Ashburn",
        country="United States",
        country_code="US",
        region="Americas",
        region_group="north_america",
        is_primary_region=True,
        priority_weight=50,
        supports_wireguard=True,
    )
    _create_server(
        db,
        server_id="eu-primary",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        region_group="europe",
        is_primary_region=True,
        priority_weight=1,
        supports_wireguard=True,
    )
    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "na-primary", "status": "up", "reason_code": "listener_up"},
            {"server_id": "eu-primary", "status": "up", "reason_code": "listener_up"},
        ],
    )

    response = client.get(
        "/api/vpn/resolve-region",
        params={"protocol": "wireguard", "device_type": "linux"},
        headers={**auth_headers, "X-Forwarded-For": "203.0.113.42"},
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["user_country_code"] == "BB"
    assert payload["selected_region_id"] == "na-primary"
    assert payload["selected_region_group"] == "north_america"
    assert payload["reason"] == "barbados_na_primary"


def test_resolve_region_uses_europe_fallback_when_north_america_down_for_barbados(
    client,
    auth_headers,
    db,
    monkeypatch,
):
    monkeypatch.setenv(
        "SECUREWAVE_LIGHT_GEOIP_CIDR_MAP",
        '{"203.0.113.0/24":"BB"}',
    )
    _create_server(
        db,
        server_id="na-down",
        city="Ashburn",
        country="United States",
        country_code="US",
        region="Americas",
        region_group="north_america",
        is_primary_region=True,
        priority_weight=5,
        supports_wireguard=True,
    )
    _create_server(
        db,
        server_id="eu-up",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        region_group="europe",
        is_primary_region=True,
        priority_weight=30,
        supports_wireguard=True,
    )
    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "na-down", "status": "down", "reason_code": "host_unreachable"},
            {"server_id": "eu-up", "status": "up", "reason_code": "listener_up"},
        ],
    )

    response = client.get(
        "/api/vpn/resolve-region",
        params={"protocol": "wireguard", "device_type": "linux"},
        headers={**auth_headers, "X-Forwarded-For": "203.0.113.77"},
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["user_country_code"] == "BB"
    assert payload["selected_region_id"] == "eu-up"
    assert payload["selected_region_group"] == "europe"
    assert payload["reason"] == "barbados_eu_fallback"


def test_resolve_region_preserves_manual_override_even_with_geo_strategy(client, auth_headers, db, monkeypatch):
    monkeypatch.setenv(
        "SECUREWAVE_LIGHT_GEOIP_CIDR_MAP",
        '{"203.0.113.0/24":"BB"}',
    )
    _create_server(
        db,
        server_id="na-primary-2",
        city="Ashburn",
        country="United States",
        country_code="US",
        region="Americas",
        region_group="north_america",
        is_primary_region=True,
        supports_wireguard=True,
    )
    _create_server(
        db,
        server_id="eu-manual",
        city="Frankfurt",
        country="Germany",
        country_code="DE",
        region="Europe",
        region_group="europe",
        is_primary_region=False,
        supports_wireguard=True,
    )
    _set_health_override(
        client,
        auth_headers,
        overrides=[
            {"server_id": "na-primary-2", "status": "up", "reason_code": "listener_up"},
            {"server_id": "eu-manual", "status": "up", "reason_code": "listener_up"},
        ],
    )

    response = client.get(
        "/api/vpn/resolve-region",
        params={
            "protocol": "wireguard",
            "device_type": "linux",
            "preferred_region": "eu-manual",
        },
        headers={**auth_headers, "X-Forwarded-For": "203.0.113.91"},
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["selected_region_id"] == "eu-manual"
    assert payload["reason"] in {"preferred_primary", "preferred_region_healthy"}
