from __future__ import annotations

import math

from models.vpn_server import VPNServer
from services.tunnel_runtime import reset_tunnel_runtime_for_tests


def _create_server(
    db,
    *,
    server_id: str,
    city: str,
    country: str,
    tier_restriction: str | None = None,
):
    server = VPNServer(
        server_id=server_id,
        location=city,
        country=country,
        country_code="US" if country == "United States" else "DE",
        city=city,
        region="Americas" if country == "United States" else "Europe",
        hcloud_location="ash",
        public_ip=f"203.0.113.{11 + len(server_id)}",
        endpoint=f"203.0.113.{11 + len(server_id)}:51820",
        wg_public_key=f"{server_id}-wg-public",
        wg_private_key_encrypted=f"{server_id}-wg-private",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        supports_wireguard=True,
        supports_openvpn=True,
        supports_ikev2=True,
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST_IKEV2\n-----END CERTIFICATE-----",
        ikev2_remote_id="vpn.example.test",
        tier_restriction=tier_restriction,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_simulated_usage_gauge_flow_updates_account_usage(
    client,
    db,
    monkeypatch,
    free_auth_headers,
):
    monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", "simulated")
    reset_tunnel_runtime_for_tests()
    free = _create_server(
        db,
        server_id="sim-free-1",
        city="New York",
        country="United States",
        tier_restriction=None,
    )

    connect = client.post(
        "/api/vpn/connect",
        json={"server_id": free.server_id, "protocol": "wireguard"},
        headers=free_auth_headers,
    )
    assert connect.status_code == 200, connect.text
    connect_data = connect.json()
    assert connect_data["mode"] == "simulated"
    assert connect_data["status"] == "CONNECTED"

    baseline = client.get("/api/account/usage", headers=free_auth_headers)
    assert baseline.status_code == 200, baseline.text
    base_payload = baseline.json()
    assert base_payload["plan_tier"] == "free"
    assert base_payload["quota_bytes"] == 5 * 1024 * 1024 * 1024

    freeze = client.post(
        "/api/vpn/simulate/traffic",
        json={"rx_rate_bytes_per_sec": 0, "tx_rate_bytes_per_sec": 0},
        headers=free_auth_headers,
    )
    assert freeze.status_code == 200, freeze.text

    one_hundred_mb = 100 * 1024 * 1024
    inject = client.post(
        "/api/vpn/simulate/traffic",
        json={"rx_bytes": one_hundred_mb, "tx_bytes": 0},
        headers=free_auth_headers,
    )
    assert inject.status_code == 200, inject.text

    usage = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage.status_code == 200, usage.text
    payload = usage.json()
    expected_percent = (one_hundred_mb / (5 * 1024 * 1024 * 1024)) * 100
    assert payload["used_bytes"] >= one_hundred_mb
    assert math.isclose(payload["used_percent"], expected_percent, rel_tol=0.05)


def test_free_user_premium_region_is_blocked_with_typed_error(
    client,
    db,
    monkeypatch,
    free_auth_headers,
):
    monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", "simulated")
    reset_tunnel_runtime_for_tests()
    premium = _create_server(
        db,
        server_id="sim-premium-1",
        city="Frankfurt",
        country="Germany",
        tier_restriction="premium",
    )
    resp = client.post(
        "/api/vpn/connect",
        json={"server_id": premium.server_id, "protocol": "wireguard"},
        headers=free_auth_headers,
    )
    assert resp.status_code == 403, resp.text
    payload = resp.json()
    err = payload.get("error") or {}
    assert err.get("code") == "region_premium_required"


def test_premium_user_can_connect_to_premium_region(
    client,
    db,
    monkeypatch,
    premium_auth_headers,
):
    monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", "simulated")
    reset_tunnel_runtime_for_tests()
    premium = _create_server(
        db,
        server_id="sim-premium-2",
        city="Frankfurt",
        country="Germany",
        tier_restriction="premium",
    )
    resp = client.post(
        "/api/vpn/connect",
        json={"server_id": premium.server_id, "protocol": "wireguard"},
        headers=premium_auth_headers,
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["mode"] == "simulated"
    assert payload["status"] == "CONNECTED"


def test_simulated_mode_connect_does_not_use_wireguard_runtime(
    client,
    db,
    monkeypatch,
    free_auth_headers,
):
    monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", "simulated")
    reset_tunnel_runtime_for_tests()
    free = _create_server(
        db,
        server_id="sim-free-2",
        city="New York",
        country="United States",
        tier_restriction=None,
    )

    def _explode(*args, **kwargs):  # pragma: no cover - should never execute
        raise AssertionError("wireguard runtime should not be called in simulated mode")

    monkeypatch.setattr("services.wireguard_service.WireGuardService.generate_keypair", _explode)
    monkeypatch.setattr("services.wireguard_service.WireGuardService.allocate_ip", _explode)

    resp = client.post(
        "/api/vpn/connect",
        json={"server_id": free.server_id, "protocol": "wireguard"},
        headers=free_auth_headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["mode"] == "simulated"


def test_simulated_usage_does_not_double_count_on_reconnect_or_after_disconnect(
    client,
    db,
    monkeypatch,
    free_auth_headers,
):
    monkeypatch.setenv("SECUREWAVE_TUNNEL_MODE", "simulated")
    monkeypatch.setenv("SECUREWAVE_SIM_RX_RATE_BYTES_PER_SEC", "0")
    monkeypatch.setenv("SECUREWAVE_SIM_TX_RATE_BYTES_PER_SEC", "0")
    reset_tunnel_runtime_for_tests()
    free = _create_server(
        db,
        server_id="sim-free-reconnect",
        city="New York",
        country="United States",
        tier_restriction=None,
    )

    connect1 = client.post(
        "/api/vpn/connect",
        json={"server_id": free.server_id, "protocol": "wireguard"},
        headers=free_auth_headers,
    )
    assert connect1.status_code == 200, connect1.text

    first_transfer = 64 * 1024 * 1024
    inject1 = client.post(
        "/api/vpn/simulate/traffic",
        json={"rx_bytes": first_transfer, "tx_bytes": 0},
        headers=free_auth_headers,
    )
    assert inject1.status_code == 200, inject1.text

    usage1 = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage1.status_code == 200, usage1.text
    used_after_first = int(usage1.json()["used_bytes"])
    assert used_after_first >= first_transfer
    devices_count = int(usage1.json()["devices_count"])

    disconnect = client.post("/api/vpn/disconnect", headers=free_auth_headers)
    assert disconnect.status_code == 200, disconnect.text

    usage_after_disconnect = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage_after_disconnect.status_code == 200, usage_after_disconnect.text
    assert int(usage_after_disconnect.json()["used_bytes"]) == used_after_first
    assert int(usage_after_disconnect.json()["devices_count"]) == devices_count

    # Repeated reads after disconnect must not keep incrementing usage.
    usage_after_disconnect_2 = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage_after_disconnect_2.status_code == 200, usage_after_disconnect_2.text
    assert int(usage_after_disconnect_2.json()["used_bytes"]) == used_after_first

    connect2 = client.post(
        "/api/vpn/connect",
        json={"server_id": free.server_id, "protocol": "wireguard"},
        headers=free_auth_headers,
    )
    assert connect2.status_code == 200, connect2.text

    usage_after_reconnect = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage_after_reconnect.status_code == 200, usage_after_reconnect.text
    assert int(usage_after_reconnect.json()["used_bytes"]) == used_after_first

    second_transfer = 16 * 1024 * 1024
    inject2 = client.post(
        "/api/vpn/simulate/traffic",
        json={"rx_bytes": second_transfer, "tx_bytes": 0},
        headers=free_auth_headers,
    )
    assert inject2.status_code == 200, inject2.text

    usage2 = client.get("/api/account/usage", headers=free_auth_headers)
    assert usage2.status_code == 200, usage2.text
    used_after_second = int(usage2.json()["used_bytes"])
    assert used_after_second >= used_after_first + second_transfer
