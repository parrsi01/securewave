from models.vpn_server import VPNServer
from routes import vpn as vpn_routes


def _create_server(db, server_id: str) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Ashburn, US",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        region_group="north_america",
        hcloud_location="ash",
        public_ip="10.10.10.10",
        endpoint="10.10.10.10:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        hcloud_server_state="running",
        supports_wireguard=True,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_region_probe_circuit_opens_after_repeated_failures(db, monkeypatch):
    monkeypatch.setenv("SECUREWAVE_REGION_HEALTH_ACTIVE_PROBE", "true")
    monkeypatch.setenv("SECUREWAVE_REGION_HEALTH_CACHE_TTL_SECONDS", "0")
    monkeypatch.setenv("SECUREWAVE_REGION_PROBE_FAILURE_THRESHOLD", "2")
    monkeypatch.setenv("SECUREWAVE_REGION_PROBE_COOLDOWN_SECONDS", "60")
    monkeypatch.setattr(vpn_routes, "_probe_region_health", lambda _server: ("down", "timeout"))

    vpn_routes._REGION_HEALTH_CACHE.clear()
    vpn_routes._REGION_PROBE_CIRCUITS.clear()
    vpn_routes._TEST_REGION_HEALTH_OVERRIDES.clear()

    server = _create_server(db, "circuit-open-1")

    first = vpn_routes._region_health_for_server(server, force_refresh=True)
    second = vpn_routes._region_health_for_server(server, force_refresh=True)
    third = vpn_routes._region_health_for_server(server, force_refresh=True)

    assert first["status"] == "down"
    assert second["status"] == "down"
    assert third["status"] == "down"
    assert third["reason_code"] == "circuit_open"


def test_region_watchdog_marks_server_unreachable_after_threshold(db, monkeypatch):
    monkeypatch.setenv("SECUREWAVE_REGION_HEALTH_ACTIVE_PROBE", "true")
    monkeypatch.setenv("SECUREWAVE_REGION_HEALTH_CACHE_TTL_SECONDS", "0")
    monkeypatch.setenv("SECUREWAVE_REGION_PROBE_FAILURE_THRESHOLD", "2")
    monkeypatch.setattr(vpn_routes, "_probe_region_health", lambda _server: ("down", "host_unreachable"))

    vpn_routes._REGION_HEALTH_CACHE.clear()
    vpn_routes._REGION_PROBE_CIRCUITS.clear()
    vpn_routes._TEST_REGION_HEALTH_OVERRIDES.clear()

    _create_server(db, "watchdog-down-1")

    first = vpn_routes.run_region_health_watchdog_cycle(db)
    second = vpn_routes.run_region_health_watchdog_cycle(db)

    refreshed = db.query(VPNServer).filter(VPNServer.server_id == "watchdog-down-1").first()
    assert first["checked"] == 1
    assert second["checked"] == 1
    assert refreshed is not None
    assert refreshed.health_status == "unreachable"
    assert int(refreshed.consecutive_health_failures or 0) >= 2
