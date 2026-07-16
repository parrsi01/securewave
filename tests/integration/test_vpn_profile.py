from datetime import datetime, timedelta
import re

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
            "wireguard": {"healthy": True, "authenticated": True, "observed_at": observed_at.isoformat()}
        },
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        openvpn_requires_client_cert=False,
        openvpn_supports_userpass=True,
    )
    data.update(overrides)
    server = VPNServer(**data)
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _ikev2_evidence(
    observed_at: datetime,
    *,
    healthy: bool = True,
    data_plane_healthy: bool = True,
    data_plane_observed_at: datetime | None = None,
):
    evidence = {
        "healthy": healthy,
        "authenticated": True,
        "data_plane_healthy": data_plane_healthy,
        "observed_at": observed_at.isoformat(),
    }
    if data_plane_observed_at is not None:
        evidence["data_plane_observed_at"] = data_plane_observed_at.isoformat()
    return {"ikev2": evidence}


def _ready_ikev2_server(db, *, server_id="profile-ikev2-us-1", **overrides):
    observed_at = datetime.utcnow()
    data = {
        "supports_ikev2": True,
        "ikev2_remote_id": "vpn.securewave.test",
        "ikev2_ca_cert_pem": (
            "-----BEGIN CERTIFICATE-----\n"
            "MIIBtest\n"
            "-----END CERTIFICATE-----"
        ),
        "protocol_runtime_evidence": _ikev2_evidence(observed_at),
    }
    data.update(overrides)
    return _create_free_server(db, server_id=server_id, **data)


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

    def test_profile_reuses_single_active_device_after_reinstall_name_change(
        self, client, auth_headers, db
    ):
        """A regenerated Flutter name must not consume a second free-tier slot."""
        _create_free_server(db, server_id="profile-reuse-linux-1")

        first = client.post(
            "/api/vpn/profile",
            json={"device_name": "Old Linux install", "device_type": "linux"},
            headers=auth_headers,
        )
        assert first.status_code == status.HTTP_200_OK, first.text
        first_device_id = first.json()["device_id"]

        second = client.post(
            "/api/vpn/profile",
            json={"device_name": "Linux device (fresh-install)", "device_type": "linux"},
            headers=auth_headers,
        )
        assert second.status_code == status.HTTP_200_OK, second.text
        assert second.json()["device_id"] == first_device_id

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

    def test_protocols_endpoint_keeps_ikev2_unavailable_even_when_server_flags_are_set(
        self, client, auth_headers, db
    ):
        _create_free_server(db, supports_openvpn=True, supports_ikev2=True)

        resp = client.get(
            "/api/vpn/protocols?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        protocols = {item["protocol"]: item for item in data["protocols"]}
        assert data["runtime_contract"] == "openvpn-evidence-v2"
        assert protocols["wireguard"]["enabled"] is True
        assert protocols["openvpn"]["enabled"] is False
        assert protocols["ikev2"]["enabled"] is False
        assert protocols["ikev2"]["platform_supported"] is False
        assert "unavailable" in (protocols["ikev2"]["reason"] or "").lower()

    def test_servers_endpoint_returns_supported_protocols(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            protocol_runtime_evidence={
                "wireguard": {"healthy": True, "authenticated": True, "observed_at": datetime.utcnow().isoformat()},
                "openvpn": {
                    "healthy": True,
                    "authenticated": True,
                    "data_plane_healthy": True,
                    "observed_at": datetime.utcnow().isoformat(),
                }
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

    def test_server_inventory_does_not_advertise_unauthenticated_wireguard(
        self, client, auth_headers, db
    ):
        _create_free_server(
            db,
            server_id="profile-unauthenticated-wireguard",
            protocol_runtime_evidence={
                "wireguard": {
                    "healthy": True,
                    "observed_at": datetime.utcnow().isoformat(),
                }
            },
        )

        response = client.get(
            "/api/vpn/servers?device_type=linux", headers=auth_headers
        )
        assert response.status_code == status.HTTP_200_OK
        server = response.json()["servers"][0]
        assert server["supports_wireguard"] is False
        assert "wireguard" not in server["supported_protocols"]

        profile = client.post(
            "/api/vpn/profile",
            headers=auth_headers,
            json={
                "device_name": "No authenticated evidence",
                "device_type": "linux",
                "server_id": server["server_id"],
            },
        )
        assert profile.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "wireguard" not in profile.text

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
                "openvpn": {
                    "healthy": True,
                    "authenticated": True,
                    "data_plane_healthy": True,
                    "observed_at": datetime.utcnow().isoformat(),
                }
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

    def test_openvpn_runtime_without_data_plane_evidence_fails_closed(
        self, client, auth_headers, db
    ):
        server = _create_free_server(
            db,
            server_id="profile-openvpn-no-data-plane",
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            protocol_runtime_evidence={
                "openvpn": {
                    "healthy": True,
                    "authenticated": True,
                    "observed_at": datetime.utcnow().isoformat(),
                }
            },
        )
        response = client.get("/api/vpn/protocols?device_type=linux", headers=auth_headers)
        openvpn = next(item for item in response.json()["protocols"] if item["protocol"] == "openvpn")
        assert openvpn["enabled"] is False
        assert "data-plane" in (openvpn["reason"] or "")

        profile = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "OpenVPN without data plane",
                "device_type": "linux",
                "protocol": "openvpn",
                "server_id": server.server_id,
            },
            headers=auth_headers,
        )
        # A controlled certification run may bootstrap a profile before the
        # global data-plane evidence is recorded; normal API callers remain
        # fail-closed at the protocol listing endpoint above.
        assert profile.status_code == status.HTTP_200_OK, profile.text
        assert profile.json()["protocol"] == "openvpn"

    def test_ikev2_remains_unavailable_even_with_complete_server_evidence(
        self, client, auth_headers, db
    ):
        _ready_ikev2_server(db)

        protocols_response = client.get(
            "/api/vpn/protocols?device_type=linux",
            headers=auth_headers,
        )
        assert protocols_response.status_code == status.HTTP_200_OK
        ikev2 = next(
            item
            for item in protocols_response.json()["protocols"]
            if item["protocol"] == "ikev2"
        )
        assert ikev2["enabled"] is False
        assert ikev2["server_enabled"] is False
        assert ikev2["platform_supported"] is False
        assert "unavailable" in ikev2["reason"].lower()

        servers_response = client.get(
            "/api/vpn/servers?device_type=linux",
            headers=auth_headers,
        )
        server = servers_response.json()["servers"][0]
        assert server["supports_ikev2"] is False
        assert "ikev2" not in server["supported_protocols"]

        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "ikev2",
            },
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "unavailable" in response.text.lower()

    @pytest.mark.parametrize(
        "evidence_case",
        [
            "missing-protocol-evidence",
            "unhealthy-protocol-evidence",
            "missing-data-plane-health",
            "unhealthy-data-plane-health",
            "stale-protocol-evidence",
            "future-protocol-evidence",
            "stale-data-plane-evidence",
            "future-data-plane-evidence",
        ],
    )
    def test_ikev2_missing_stale_or_future_evidence_fails_closed(
        self, client, auth_headers, db, evidence_case
    ):
        now = datetime.utcnow()
        evidence_by_case = {
            "missing-protocol-evidence": None,
            "unhealthy-protocol-evidence": _ikev2_evidence(now, healthy=False),
            "missing-data-plane-health": {
                "ikev2": {"healthy": True, "authenticated": True, "observed_at": now.isoformat()}
            },
            "unhealthy-data-plane-health": _ikev2_evidence(
                now,
                data_plane_healthy=False,
            ),
            "stale-protocol-evidence": _ikev2_evidence(now - timedelta(hours=2)),
            "future-protocol-evidence": _ikev2_evidence(now + timedelta(minutes=10)),
            "stale-data-plane-evidence": _ikev2_evidence(
                now,
                data_plane_observed_at=now - timedelta(hours=2),
            ),
            "future-data-plane-evidence": _ikev2_evidence(
                now,
                data_plane_observed_at=now + timedelta(minutes=10),
            ),
        }
        server = _ready_ikev2_server(
            db,
            server_id="profile-ikev2-invalid-evidence",
            protocol_runtime_evidence=evidence_by_case[evidence_case],
        )

        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "IKEv2 invalid evidence",
                "device_type": "linux",
                "protocol": "ikev2",
                "server_id": server.server_id,
            },
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "ikev2_config" not in response.text

    @pytest.mark.parametrize(
        "overrides",
        [
            {"supports_ikev2": False},
            {"endpoint": "", "public_ip": ""},
            {"endpoint": ":51820"},
            {"endpoint": "host.invalid:not-a-port"},
            {"ikev2_remote_id": None, "public_ip": ""},
            {"ikev2_ca_cert_pem": None},
            {"ikev2_ca_cert_pem": "not-a-certificate"},
        ],
        ids=[
            "server-support-disabled",
            "missing-endpoint",
            "empty-endpoint-host",
            "invalid-endpoint-port",
            "missing-remote-id",
            "missing-ca",
            "malformed-ca",
        ],
    )
    def test_ikev2_missing_support_or_metadata_fails_closed(
        self, client, auth_headers, db, overrides
    ):
        server = _ready_ikev2_server(
            db,
            server_id="profile-ikev2-invalid-metadata",
            **overrides,
        )

        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "IKEv2 invalid metadata",
                "device_type": "linux",
                "protocol": "ikev2",
                "server_id": server.server_id,
            },
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "ikev2 is unavailable" in response.text.lower()
        assert "ikev2_config" not in response.text

    @pytest.mark.parametrize("legacy_secret", [None, "", " \t", "line1\nline2"])
    def test_ikev2_ignores_legacy_global_eap_secret(
        self, client, auth_headers, db, monkeypatch, legacy_secret
    ):
        if legacy_secret is None:
            monkeypatch.delenv("SECUREWAVE_IKEV2_EAP_SECRET", raising=False)
        else:
            monkeypatch.setenv("SECUREWAVE_IKEV2_EAP_SECRET", legacy_secret)
        server = _ready_ikev2_server(
            db,
            server_id="profile-ikev2-legacy-secret",
        )

        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "IKEv2 independent secret",
                "device_type": "linux",
                "protocol": "ikev2",
                "server_id": server.server_id,
            },
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE, response.text
        assert "unavailable" in response.text.lower()

    @pytest.mark.parametrize(
        "state_case",
        [
            "inactive",
            "unhealthy",
            "missing-common-health",
            "stale-common-health",
            "future-common-health",
            "zero-capacity",
            "negative-current-capacity",
            "full-capacity",
            "missing-provider-state",
            "stopped-provider",
        ],
    )
    def test_ikev2_common_runtime_state_must_be_usable(
        self, client, auth_headers, db, state_case
    ):
        now = datetime.utcnow()
        overrides_by_case = {
            "inactive": {"status": "maintenance"},
            "unhealthy": {"health_status": "unhealthy"},
            "missing-common-health": {"last_health_check": None},
            "stale-common-health": {"last_health_check": now - timedelta(hours=2)},
            "future-common-health": {"last_health_check": now + timedelta(minutes=10)},
            "zero-capacity": {"max_connections": 0},
            "negative-current-capacity": {"current_connections": -1},
            "full-capacity": {"max_connections": 10, "current_connections": 10},
            "missing-provider-state": {"hcloud_server_state": None},
            "stopped-provider": {"hcloud_server_state": "stopped"},
        }
        server = _ready_ikev2_server(
            db,
            server_id="profile-ikev2-invalid-common-state",
            **overrides_by_case[state_case],
        )

        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "IKEv2 invalid common state",
                "device_type": "linux",
                "protocol": "ikev2",
                "server_id": server.server_id,
            },
            headers=auth_headers,
        )
        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "ikev2_config" not in response.text

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
                "wireguard": {"healthy": True, "authenticated": True, "observed_at": future_at.isoformat()}
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

        from services.wireguard_peer_lifecycle import WireGuardPeerSyncError

        async def registration_failed(*_args, **_kwargs):
            raise WireGuardPeerSyncError("backend unavailable")

        monkeypatch.setattr(vpn_routes, "confirm_peer_assignment", registration_failed)
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
        async def authenticated_health_check(self, _connection):
            return True, True, "sensitive manager output must not be persisted"

    monkeypatch.setattr(monitor_module, "wg_mock_mode_enabled", lambda: False)
    monkeypatch.setattr(monitor_module, "get_wireguard_server_manager", lambda: FakeManager())
    monkeypatch.setattr(monitor_module, "server_connection_from_db", lambda _server: object())

    monitor = VPNHealthMonitor()
    monitor.db = db
    assert await monitor._probe_wireguard_runtime(server) is True

    db.refresh(server)
    evidence = server.protocol_runtime_evidence["wireguard"]
    assert evidence["healthy"] is True
    assert evidence["authenticated"] is True
    assert evidence["transition"] == "initial"
    assert set(evidence) == {"healthy", "observed_at", "transition", "authenticated"}
    assert "sensitive" not in str(server.protocol_runtime_evidence)
