import pytest
from fastapi import status


def _create_free_server(db):
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="profile-free-us-1",
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
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_premium_server(db):
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="profile-premium-us-1",
        location="New York, US (Premium)",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        hcloud_location="ash",
        public_ip="10.0.0.99",
        endpoint="10.0.0.99:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LXByb2ZpbGUtcHJlbWl1bQ==",
        wg_private_key_encrypted="encrypted-private-key-premium",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction="premium",
        performance_score=99.0,
        hcloud_server_state="running",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_openvpn_server(db):
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="profile-openvpn-us-1",
        location="New York, US (OpenVPN)",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        hcloud_location="ash",
        public_ip="10.0.0.55",
        endpoint="10.0.0.55:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LW9wZW52cG4=",
        wg_private_key_encrypted="encrypted-private-key-openvpn",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=True,
        supports_openvpn=True,
        openvpn_port=1194,
        openvpn_transport="udp",
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_ikev2_server(db):
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="profile-ikev2-us-1",
        location="New York, US (IKEv2)",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        hcloud_location="ash",
        public_ip="10.0.0.66",
        endpoint="10.0.0.66:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LWlrZXYy",
        wg_private_key_encrypted="encrypted-private-key-ikev2",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=True,
        supports_ikev2=True,
        ikev2_remote_id="vpn.example.test",
    )
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
        assert ks.get("mode") == "disabled"
        assert ks.get("enforcement") == "none"

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

    def test_free_user_cannot_request_premium_server(self, client, auth_headers, db):
        """
        Premium/free isolation hardening: free tier must not be able to force-select
        a tier-restricted server via POST /api/vpn/profile.
        """
        _create_free_server(db)
        premium = _create_premium_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Free Device", "device_type": "linux", "server_id": premium.server_id},
            headers=auth_headers,
        )
        assert resp.status_code == status.HTTP_403_FORBIDDEN, resp.text
        body = resp.json()
        # ApiException format
        err = body.get("error") or {}
        assert err.get("code") == "server_tier_restricted"

    def test_free_user_profile_does_not_stick_to_premium_peer_server(self, client, auth_headers, db):
        """
        If a peer is (incorrectly) associated with a premium server in DB, free-tier
        profile issuance must ignore that association and auto-select an allowed server.
        """
        free = _create_free_server(db)
        premium = _create_premium_server(db)

        # First, issue a profile so a peer/device exists.
        first = client.post(
            "/api/vpn/profile",
            json={"device_name": "Sticky Device", "device_type": "linux"},
            headers=auth_headers,
        )
        assert first.status_code == 200, first.text
        device_id = first.json().get("device_id")
        assert device_id

        # Force the peer server_id to the premium server (simulate inconsistent state).
        from models.wireguard_peer import WireGuardPeer

        peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == int(device_id)).first()
        assert peer is not None
        peer.server_id = premium.id
        db.add(peer)
        db.commit()

        # Second profile call should not return the premium server for free-tier.
        second = client.post(
            "/api/vpn/profile",
            json={"device_id": device_id, "device_type": "linux"},
            headers=auth_headers,
        )
        assert second.status_code == 200, second.text
        assert second.json().get("server_id") == free.server_id

    def test_openvpn_profile_returns_ovpn_and_certificate_metadata(self, client, auth_headers, db):
        _create_free_server(db)
        openvpn = _create_openvpn_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Win Box", "device_type": "windows", "protocol": "openvpn", "server_id": openvpn.server_id},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("protocol") == "openvpn"
        assert data.get("server_id") == openvpn.server_id
        profile = data.get("profile") or {}
        assert profile.get("type") == "openvpn"
        assert profile.get("auth_method") == "mtls"
        assert "client" in (profile.get("ovpn_config") or "")
        assert profile.get("username")
        assert profile.get("cert_serial")
        assert profile.get("cert_fingerprint_sha256")

    def test_openvpn_request_returns_typed_error_when_unavailable(self, client, auth_headers, db):
        _create_free_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Win Box", "device_type": "windows", "protocol": "openvpn"},
            headers=auth_headers,
        )
        assert resp.status_code == 409, resp.text
        body = resp.json()
        err = body.get("error") or {}
        assert err.get("code") == "protocol_temporarily_unavailable"

    def test_explicit_server_rejects_unsupported_protocol(self, client, auth_headers, db):
        free = _create_free_server(db)
        _create_openvpn_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Win Box", "device_type": "windows", "protocol": "openvpn", "server_id": free.server_id},
            headers=auth_headers,
        )
        assert resp.status_code == 409, resp.text
        body = resp.json()
        err = body.get("error") or {}
        assert err.get("code") == "protocol_not_supported_on_server"

    def test_ikev2_profile_returns_structured_payload(self, client, auth_headers, db):
        ikev2 = _create_ikev2_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Win Box", "device_type": "windows", "protocol": "ikev2", "server_id": ikev2.server_id},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("protocol") == "ikev2"
        profile = data.get("profile") or {}
        assert profile.get("type") == "ikev2"
        assert profile.get("auth_method") == "eap-tls"
        assert profile.get("server")
        assert profile.get("username")
        assert profile.get("client_pkcs12_base64")
        assert profile.get("client_pkcs12_password")

    def test_explicit_protocol_rejected_for_unsupported_platform(self, client, auth_headers, db):
        _create_openvpn_server(db)

        resp = client.post(
            "/api/vpn/profile",
            json={"device_name": "Android Phone", "device_type": "android", "protocol": "openvpn"},
            headers=auth_headers,
        )
        assert resp.status_code == 400, resp.text
        body = resp.json()
        err = body.get("error") or {}
        assert err.get("code") == "protocol_not_supported_on_platform"
