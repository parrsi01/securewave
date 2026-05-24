import pytest
from fastapi import status


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
        assert "No openvpn VPN servers available" in resp.text

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

    def test_ikev2_profile_returns_protocol_config_when_server_supports_it(self, client, auth_headers, db):
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
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("protocol") == "ikev2"
        assert "connections" in data.get("ikev2_config", "")
        assert "vpn.securewave.test" in data.get("ikev2_config", "")
