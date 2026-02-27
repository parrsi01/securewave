from __future__ import annotations

from typing import Any

from models.vpn_server import VPNServer
from services.tunnel_runtime import reset_tunnel_runtime_for_tests


REQUIRED_USAGE_KEYS = {
    "quota_bytes",
    "used_bytes",
    "used_percent",
    "plan_tier",
    "devices_count",
    "username",
    "display_name",
}

REQUIRED_REGION_KEYS = {
    "server_id",
    "region_health_status",
    "region_health_last_checked_at",
    "region_health_reason_code",
}

REQUIRED_PROTOCOL_KEYS = {
    "protocol",
    "enabled",
    "server_enabled",
    "plan_enabled",
    "platform_supported",
    "health_status",
    "health_reason",
    "reason",
}


def _create_server(db, *, server_id: str, supports_openvpn: bool, supports_ikev2: bool) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="New York",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        region_group="north_america",
        hcloud_location="ash",
        public_ip=f"203.0.113.{10 + len(server_id)}",
        endpoint=f"203.0.113.{10 + len(server_id)}:51820",
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
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _shape(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _shape(value[key]) for key in sorted(value.keys())}
    if isinstance(value, list):
        if not value:
            return ["empty"]
        return [_shape(value[0])]
    if value is None:
        return "null"
    return type(value).__name__


def test_api_contract_required_keys_and_types(client, auth_headers, db):
    _create_server(db, server_id="contract-wg", supports_openvpn=False, supports_ikev2=False)
    _create_server(db, server_id="contract-all", supports_openvpn=True, supports_ikev2=True)

    usage_resp = client.get("/api/account/usage", headers=auth_headers)
    assert usage_resp.status_code == 200, usage_resp.text
    usage = usage_resp.json()
    assert REQUIRED_USAGE_KEYS.issubset(usage.keys())
    assert isinstance(usage["quota_bytes"], int)
    assert isinstance(usage["used_bytes"], int)
    assert isinstance(usage["used_percent"], (int, float))
    assert isinstance(usage["plan_tier"], str)
    assert isinstance(usage["devices_count"], int)
    assert isinstance(usage["username"], str)
    assert isinstance(usage["display_name"], str)

    regions_resp = client.get("/api/vpn/regions", headers=auth_headers)
    assert regions_resp.status_code == 200, regions_resp.text
    regions_payload = regions_resp.json()
    assert "regions" in regions_payload
    assert isinstance(regions_payload["regions"], list)
    assert regions_payload["regions"], "expected seeded regions"
    for row in regions_payload["regions"]:
        assert REQUIRED_REGION_KEYS.issubset(row.keys())
        assert row["region_health_status"] in {"up", "down", "unknown"}
        assert row["region_health_last_checked_at"] is None or isinstance(
            row["region_health_last_checked_at"], str
        )
        assert row["region_health_reason_code"] is None or isinstance(
            row["region_health_reason_code"], str
        )

    protocols_resp = client.get(
        "/api/vpn/protocols",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert protocols_resp.status_code == 200, protocols_resp.text
    protocols_payload = protocols_resp.json()
    assert "protocols" in protocols_payload
    assert isinstance(protocols_payload["protocols"], list)
    for row in protocols_payload["protocols"]:
        assert REQUIRED_PROTOCOL_KEYS.issubset(row.keys())
        assert isinstance(row["protocol"], str)
        assert isinstance(row["enabled"], bool)
        assert isinstance(row["server_enabled"], bool)
        assert isinstance(row["plan_enabled"], bool)
        assert isinstance(row["platform_supported"], bool)

    compat_resp = client.get(
        "/api/vpn/protocol-capabilities",
        params={"device_type": "linux"},
        headers=auth_headers,
    )
    assert compat_resp.status_code == 200, compat_resp.text
    assert _shape(compat_resp.json()) == _shape(protocols_payload)


def test_api_contract_shape_matches_between_simulated_and_real_modes(
    client,
    auth_headers,
    db,
    monkeypatch,
):
    _create_server(db, server_id="shape-wg", supports_openvpn=True, supports_ikev2=True)

    def collect_shapes(mode: str) -> dict[str, Any]:
        monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", mode)
        reset_tunnel_runtime_for_tests()
        usage = client.get("/api/account/usage", headers=auth_headers)
        regions = client.get("/api/vpn/regions", headers=auth_headers)
        protocols = client.get(
            "/api/vpn/protocols",
            params={"device_type": "linux"},
            headers=auth_headers,
        )
        capabilities = client.get(
            "/api/vpn/protocol-capabilities",
            params={"device_type": "linux"},
            headers=auth_headers,
        )
        assert usage.status_code == 200, usage.text
        assert regions.status_code == 200, regions.text
        assert protocols.status_code == 200, protocols.text
        assert capabilities.status_code == 200, capabilities.text
        return {
            "usage": _shape(usage.json()),
            "regions": _shape(regions.json()),
            "protocols": _shape(protocols.json()),
            "protocol_capabilities": _shape(capabilities.json()),
        }

    real_shapes = collect_shapes("real")
    simulated_shapes = collect_shapes("simulated")
    assert simulated_shapes == real_shapes
