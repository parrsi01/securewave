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

    def test_protocols_endpoint_exposes_linux_protocols_when_metadata_exists(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            supports_ikev2=True,
            ikev2_remote_id="vpn.securewave.test",
            ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        )

        resp = client.get(
            "/api/vpn/protocols?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        protocols = {item["protocol"]: item for item in data["protocols"]}
        assert protocols["wireguard"]["enabled"] is True
        assert protocols["openvpn"]["enabled"] is True
        assert protocols["ikev2"]["enabled"] is True
        assert protocols["ikev2"]["platform_supported"] is True

    def test_servers_endpoint_returns_supported_protocols(self, client, auth_headers, db):
        _create_free_server(
            db,
            supports_openvpn=True,
            openvpn_endpoint="10.0.0.9",
            openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            supports_ikev2=True,
            ikev2_remote_id="vpn.securewave.test",
            ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        )

        resp = client.get(
            "/api/vpn/servers?device_type=linux",
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        server = resp.json()["servers"][0]
        assert server["supported_protocols"] == ["wireguard", "openvpn", "ikev2"]
        assert server["supports_ikev2"] is True

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
        config = data.get("openvpn_config", "")
        assert "client" in config
        assert "<ca>" in config
        assert "auth-user-pass" not in config

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
        assert not data.get("wireguard_config")
        config = data.get("ikev2_config", "")
        assert "connections {" in config
        assert "secrets {" in config
        assert "auth = eap-mschapv2" in config
        assert "securewave-ikev2-ca.pem" in config
        assert "securewave-test-ikev2-secret" in config
