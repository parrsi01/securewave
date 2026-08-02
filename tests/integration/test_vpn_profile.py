import pytest
from fastapi import status
from models.wireguard_peer import WireGuardPeer


def _create_free_server(db, *, server_id="profile-free-us-1", **overrides):
    from models.vpn_server import VPNServer

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


def test_invalid_explicit_server_does_not_create_device_peer(
    client, auth_headers, test_user, db
):
    _create_free_server(db)

    response = client.post(
        "/api/vpn/profile",
        json={
            "device_name": "Rejected server device",
            "device_type": "linux",
            "server_id": "does-not-exist",
        },
        headers=auth_headers,
    )

    assert response.status_code == 404, response.text
    assert not db.query(WireGuardPeer).filter(
        WireGuardPeer.device_name == "Rejected server device",
        WireGuardPeer.user_id == test_user.id,
    ).first()


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

    def test_stale_device_id_falls_back_to_device_name_lookup(self, client, auth_headers, db):
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
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("device_id") != 999999
        assert data.get("protocol") == "wireguard"
        assert data.get("wireguard_config")

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

    def test_android_protocol_contract_exposes_wireguard_only(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        )

        protocols_resp = client.get(
            "/api/vpn/protocols?device_type=android",
            headers=auth_headers,
        )
        assert protocols_resp.status_code == 200, protocols_resp.text
        protocols = {item["protocol"]: item for item in protocols_resp.json()["protocols"]}
        assert protocols["wireguard"]["platform_supported"] is True
        assert protocols["openvpn"]["server_enabled"] is False
        assert protocols["openvpn"]["platform_supported"] is False
        assert protocols["openvpn"]["enabled"] is False

        profile_resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Android Phone",
                "device_type": "android",
                "protocol": "openvpn",
            },
            headers=auth_headers,
        )
        assert profile_resp.status_code == 400, profile_resp.text
        assert "not release-ready" in profile_resp.text

    def test_servers_endpoint_returns_supported_protocols(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            supports_ikev2=True,
        )

        resp = client.get(
            "/api/vpn/servers?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        server = resp.json()["servers"][0]
        assert server["supported_protocols"] == ["wireguard"]
        assert server["supports_openvpn"] is False
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
        assert "authenticated current-source" in resp.text

    def test_openvpn_profile_rejects_legacy_metadata_without_current_evidence(self, client, auth_headers, db):
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
        assert resp.status_code == 503, resp.text
        assert "authenticated current-source" in resp.text
        assert db.query(WireGuardPeer).count() == 0

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
