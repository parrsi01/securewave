from datetime import datetime, timedelta

import pytest
from fastapi import status


def _create_free_server(db, *, server_id="profile-free-us-1", **overrides):
    from models.vpn_server import VPNServer

    observed_at = datetime.utcnow()
    data = dict(
        server_id=server_id,
        location="New York, US",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        hcloud_location="ash",
        public_ip="10.0.0.9",
        endpoint="10.0.0.9:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LXByb2ZpbGU=",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        last_health_check=observed_at,
        protocol_runtime_evidence={
            "wireguard": {"healthy": True, "observed_at": observed_at.isoformat()}
        },
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
    )
    data.update(overrides)
    server = VPNServer(**data)
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


class TestVpnProfileProvisioning:
    def test_profile_returns_config_and_metadata(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Test Laptop", "device_type": "windows"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data.get("device_id")
        assert data.get("server_id")
        assert data.get("wireguard_config")
        assert "[Interface]" in data["wireguard_config"]
        assert "[Peer]" in data["wireguard_config"]
        assert "DNS =" in data["wireguard_config"]
        assert "PersistentKeepalive" in data["wireguard_config"]

        dns = data.get("dns") or {}
        assert dns.get("ad_malware_blocking") == "on"
        assert isinstance(dns.get("servers"), list)
        assert len(dns.get("servers")) >= 1

        ks = data.get("kill_switch") or {}
        assert ks.get("mode") == "enabled"
        assert ks.get("enforcement")

    def test_legacy_allocate_delegates_to_confirmed_profile_without_config_cache(
        self, client, auth_headers, db
    ):
        server = _create_free_server(db, server_id="profile-allocate-us-1")
        response = client.post(
            "/api/vpn/allocate",
            json={"device_name": "Allocation compatibility", "server_id": server.server_id},
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_200_OK, response.text
        body = response.json()
        assert body["peer_registered"] is True
        assert "PrivateKey =" in body["config"]

        from models.wireguard_peer import WireGuardPeer
        from services.wireguard_service import WireGuardService
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.device_name == "Allocation compatibility"
        ).one()
        assert not WireGuardService().config_path_for_server(peer.user_id, server.server_id).exists()

    def test_unknown_device_id_is_not_silently_created(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={
                "device_id": 999999,
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert resp.status_code == status.HTTP_404_NOT_FOUND

        from models.wireguard_peer import WireGuardPeer
        assert db.query(WireGuardPeer).count() == 0

    def test_protocols_endpoint_keeps_linux_ikev2_blocked(self, client, auth_headers, db):
        _create_free_server(db, supports_openvpn=True, supports_ikev2=True)

        resp = client.get(
            "/api/vpn/protocols?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        protocols = {item["protocol"]: item for item in data["protocols"]}
        assert protocols["wireguard"]["enabled"] is True
        assert protocols["openvpn"]["enabled"] is False
        assert protocols["ikev2"]["enabled"] is False
        assert protocols["ikev2"]["platform_supported"] is False

    def test_servers_endpoint_returns_supported_protocols(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            protocol_runtime_evidence={
                "wireguard": {"healthy": True, "observed_at": datetime.utcnow().isoformat()},
                "openvpn": {"healthy": True, "observed_at": datetime.utcnow().isoformat()}
            },
            supports_ikev2=True,
        )

        resp = client.get(
            "/api/vpn/servers?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        server = resp.json()["servers"][0]
        assert server["supported_protocols"] == ["wireguard", "openvpn"]
        assert server["supports_ikev2"] is False

    def test_linux_profile_includes_wg_quick_kill_switch_hooks(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Linux Box", "device_type": "linux"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        config = resp.json().get("wireguard_config", "")
        assert "PostUp" in config
        assert "iptables" in config

    def test_mobile_profile_does_not_include_wg_quick_hooks(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Android Phone", "device_type": "android"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        config = resp.json().get("wireguard_config", "")
        assert "PostUp" not in config

    def test_openvpn_profile_requires_server_support(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "openvpn",
            },
            headers=auth_headers,
        )
        assert resp.status_code == 503, resp.text
        assert "No usable openvpn VPN servers available" in resp.text

    def test_openvpn_profile_returns_protocol_config_when_server_supports_it(self, client, auth_headers, db):
        _create_free_server(
            db,
            server_id="profile-openvpn-us-1",
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_port=1194,
            openvpn_transport="udp",
            openvpn_ca_cert_pem=(
                "-----BEGIN CERTIFICATE-----\n"
                "MIIBtest\n"
                "-----END CERTIFICATE-----"
            ),
            protocol_runtime_evidence={
                "openvpn": {"healthy": True, "observed_at": datetime.utcnow().isoformat()}
            },
        )

        resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "openvpn",
            },
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("protocol") == "openvpn"
        assert not data.get("wireguard_config")
        assert "client" in data.get("openvpn_config", "")
        assert "<ca>" in data.get("openvpn_config", "")

    def test_openvpn_metadata_without_protocol_probe_evidence_fails_closed(self, client, auth_headers, db):
        _create_free_server(
            db,
            server_id="profile-openvpn-no-probe",
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        )
        response = client.get("/api/vpn/protocols?device_type=linux", headers=auth_headers)
        openvpn = next(item for item in response.json()["protocols"] if item["protocol"] == "openvpn")
        assert openvpn["enabled"] is False
        assert "protocol-specific" in (openvpn["reason"] or "")

    def test_ikev2_profile_is_blocked_on_linux_even_when_server_supports_it(self, client, auth_headers, db):
        _create_free_server(
            db,
            server_id="profile-ikev2-us-1",
            supports_ikev2=True,
            ikev2_remote_id="vpn.securewave.test",
            ikev2_ca_cert_pem=(
                "-----BEGIN CERTIFICATE-----\n"
                "MIIBtest\n"
                "-----END CERTIFICATE-----"
            ),
        )

        resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "ikev2",
            },
            headers=auth_headers,
        )
        assert resp.status_code == 400, resp.text
        assert "not release-ready" in resp.text

    def test_stale_runtime_evidence_fails_closed_for_listing_and_profile(self, client, auth_headers, db):
        _create_free_server(
            db,
            server_id="profile-stale-us-1",
            last_health_check=datetime.utcnow() - timedelta(hours=2),
        )

        protocols = client.get("/api/vpn/protocols?device_type=linux", headers=auth_headers)
        assert protocols.status_code == status.HTTP_200_OK
        wireguard = next(
            item for item in protocols.json()["protocols"] if item["protocol"] == "wireguard"
        )
        assert wireguard["enabled"] is False
        assert "stale" in (wireguard["reason"] or "").lower()

        profile = client.post(
            "/api/vpn/profile",
            json={"device_name": "Stale evidence", "device_type": "linux"},
            headers=auth_headers,
        )
        assert profile.status_code == status.HTTP_503_SERVICE_UNAVAILABLE

    def test_missing_and_future_runtime_evidence_fail_closed(self, client, auth_headers, db):
        missing = _create_free_server(
            db,
            server_id="profile-missing-evidence",
            protocol_runtime_evidence=None,
        )
        missing_response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Missing runtime evidence",
                "device_type": "linux",
                "server_id": missing.server_id,
            },
            headers=auth_headers,
        )
        assert missing_response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "protocol-specific" in missing_response.text.lower()

        from models.wireguard_peer import WireGuardPeer

        assert db.query(WireGuardPeer).filter(
            WireGuardPeer.device_name == "Missing runtime evidence"
        ).count() == 0

        future_at = datetime.utcnow() + timedelta(minutes=10)
        future = _create_free_server(
            db,
            server_id="profile-future-evidence",
            last_health_check=future_at,
            protocol_runtime_evidence={
                "wireguard": {"healthy": True, "observed_at": future_at.isoformat()}
            },
        )
        future_response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Future runtime evidence",
                "device_type": "linux",
                "server_id": future.server_id,
            },
            headers=auth_headers,
        )
        assert future_response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "future" in future_response.text.lower()

    def test_wireguard_registration_failure_never_issues_profile(self, client, auth_headers, db, monkeypatch):
        _create_free_server(db, server_id="profile-registration-failure")
        import routes.vpn as vpn_routes

        async def registration_failed(*_args, **_kwargs):
            return False, "backend unavailable"

        monkeypatch.setattr(vpn_routes, "register_peer_on_server", registration_failed)
        response = client.post(
            "/api/vpn/profile",
            json={"device_name": "Registration failure", "device_type": "linux"},
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "wireguard_config" not in response.text

        from models.wireguard_peer import WireGuardPeer
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.device_name == "Registration failure"
        ).one()
        assert peer.is_active is False
        assert peer.server_id is None

    def test_case_variant_profile_retry_reuses_existing_device(
        self, client, auth_headers, db
    ):
        _create_free_server(db, server_id="profile-case-retry")
        first = client.post(
            "/api/vpn/profile",
            json={"device_name": "Travel Laptop", "device_type": "linux"},
            headers=auth_headers,
        )
        second = client.post(
            "/api/vpn/profile",
            json={"device_name": "travel laptop", "device_type": "linux"},
            headers=auth_headers,
        )

        assert first.status_code == status.HTTP_200_OK, first.text
        assert second.status_code == status.HTTP_200_OK, second.text
        assert second.json()["device_id"] == first.json()["device_id"]

        from models.wireguard_peer import WireGuardPeer

        assert db.query(WireGuardPeer).count() == 1


@pytest.mark.asyncio
async def test_background_wireguard_probe_records_only_compact_runtime_evidence(
    db, monkeypatch
):
    import services.vpn_health_monitor as monitor_module
    from services.vpn_health_monitor import VPNHealthMonitor

    server = _create_free_server(
        db,
        server_id="background-wireguard-evidence",
        protocol_runtime_evidence=None,
    )

    class FakeManager:
        async def health_check(self, _connection):
            return True, "sensitive manager output must not be persisted"

    monkeypatch.setattr(monitor_module, "wg_mock_mode_enabled", lambda: False)
    monkeypatch.setattr(monitor_module, "get_wireguard_server_manager", lambda: FakeManager())
    monkeypatch.setattr(monitor_module, "server_connection_from_db", lambda _server: object())

    monitor = VPNHealthMonitor()
    monitor.db = db
    assert await monitor._probe_wireguard_runtime(server) is True

    db.refresh(server)
    evidence = server.protocol_runtime_evidence["wireguard"]
    assert evidence["healthy"] is True
    assert set(evidence) == {"healthy", "observed_at"}
    assert "sensitive" not in str(server.protocol_runtime_evidence)
    assert server.health_status == "healthy"
    assert server.consecutive_health_failures == 0


@pytest.mark.asyncio
async def test_healthy_wireguard_probe_recovers_false_unhealthy_host_metrics(
    db, monkeypatch
):
    import services.vpn_health_monitor as monitor_module
    from services.vpn_health_monitor import VPNHealthMonitor

    server = _create_free_server(db, server_id="wireguard-health-recovery")
    server.health_status = "unhealthy"
    server.consecutive_health_failures = 3
    db.commit()

    class FakeManager:
        async def health_check(self, _connection):
            return True, "authenticated management API is healthy"

    monkeypatch.setattr(monitor_module, "wg_mock_mode_enabled", lambda: False)
    monkeypatch.setattr(monitor_module, "get_wireguard_server_manager", lambda: FakeManager())
    monkeypatch.setattr(monitor_module, "server_connection_from_db", lambda _server: object())

    monitor = VPNHealthMonitor()
    monitor.db = db
    assert await monitor._probe_wireguard_runtime(server) is True

    db.refresh(server)
    assert server.health_status == "healthy"
    assert server.consecutive_health_failures == 0
    assert server.protocol_runtime_evidence["wireguard"]["healthy"] is True
