from datetime import datetime, timedelta

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

    def test_force_rotate_keys_skips_server_sync_in_mock_mode(
        self, client, auth_headers, db, monkeypatch
    ):
        import routes.vpn as vpn_routes

        _create_free_server(db)
        calls = []

        def fail_if_called():
            calls.append("manager")
            raise AssertionError("external WireGuard server sync should be skipped")

        monkeypatch.setattr(vpn_routes, "get_wireguard_server_manager", fail_if_called)

        first = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert first.status_code == 200, first.text
        device_id = first.json()["device_id"]

        rotated = client.post(
            "/api/vpn/profile",
            json={
                "device_id": device_id,
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
                "force_rotate_keys": True,
            },
            headers=auth_headers,
        )
        assert rotated.status_code == 200, rotated.text
        assert rotated.json()["key_version"] >= 2
        assert calls == []

    def test_device_rotate_keys_skips_server_sync_in_mock_mode(
        self, client, auth_headers, db, monkeypatch
    ):
        import routes.devices as device_routes

        _create_free_server(db)
        calls = []

        def fail_if_called():
            calls.append("manager")
            raise AssertionError("external WireGuard server sync should be skipped")

        monkeypatch.setattr(device_routes, "get_wireguard_server_manager", fail_if_called)

        profile = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert profile.status_code == 200, profile.text
        device_id = profile.json()["device_id"]

        rotated = client.post(
            f"/api/vpn/devices/{device_id}/rotate-keys",
            headers=auth_headers,
        )
        assert rotated.status_code == 200, rotated.text
        assert rotated.json()["key_version"] >= 2
        assert calls == []

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

    def test_usage_report_updates_free_plan_meter(self, client, auth_headers, db):
        _create_free_server(db)

        profile_resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert profile_resp.status_code == 200, profile_resp.text
        device_id = profile_resp.json()["device_id"]

        report_resp = client.post(
            "/api/vpn/usage/report",
            json={
                "device_id": device_id,
                "protocol": "wireguard",
                "rx_bytes": 1024 * 1024 * 512,
                "tx_bytes": 1024 * 1024 * 128,
            },
            headers=auth_headers,
        )
        assert report_resp.status_code == 200, report_resp.text
        report = report_resp.json()
        assert report["plan_tier"] == "free"
        assert report["data_cap_gb"] == 5
        assert report["used_gb"] == 0.625

        plan_resp = client.get("/api/user/plan", headers=auth_headers)
        assert plan_resp.status_code == 200, plan_resp.text
        assert plan_resp.json()["used_gb"] == 0.625

    def test_usage_report_accumulates_across_reconnects(self, client, auth_headers, db):
        _create_free_server(db)

        profile_resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert profile_resp.status_code == 200, profile_resp.text
        device_id = profile_resp.json()["device_id"]

        for payload in (
            {"rx_bytes": 1024 * 1024 * 512, "tx_bytes": 1024 * 1024 * 128},
            {"rx_bytes": 1024 * 1024 * 256, "tx_bytes": 0},
        ):
            report_resp = client.post(
                "/api/vpn/usage/report",
                json={
                    "device_id": device_id,
                    "protocol": "wireguard",
                    **payload,
                },
                headers=auth_headers,
            )
            assert report_resp.status_code == 200, report_resp.text

        plan_resp = client.get("/api/user/plan", headers=auth_headers)
        assert plan_resp.status_code == 200, plan_resp.text
        assert plan_resp.json()["used_gb"] == 0.875

    def test_free_plan_usage_is_current_month_when_daily_metrics_exist(
        self, client, auth_headers, db, test_user
    ):
        from models.usage_analytics import DailyUsageMetrics

        now = datetime.utcnow()
        current_month = datetime(now.year, now.month, 1)
        previous_month = current_month - timedelta(days=1)
        db.add_all(
            [
                DailyUsageMetrics(
                    user_id=test_user.id,
                    date=datetime(previous_month.year, previous_month.month, 1),
                    total_data_mb=4096,
                    data_downloaded_mb=4096,
                ),
                DailyUsageMetrics(
                    user_id=test_user.id,
                    date=current_month,
                    total_data_mb=512,
                    data_downloaded_mb=512,
                ),
            ]
        )
        db.commit()

        plan_resp = client.get("/api/user/plan", headers=auth_headers)
        assert plan_resp.status_code == 200, plan_resp.text
        assert plan_resp.json()["used_gb"] == 0.5

    def test_paid_plan_usage_uses_subscription_period(
        self, client, auth_headers, db, test_user, test_subscription
    ):
        from models.usage_analytics import DailyUsageMetrics

        period_start = datetime.utcnow() - timedelta(days=5)
        period_end = datetime.utcnow() + timedelta(days=25)
        test_subscription.current_period_start = period_start
        test_subscription.current_period_end = period_end
        db.add_all(
            [
                DailyUsageMetrics(
                    user_id=test_user.id,
                    date=period_start - timedelta(days=2),
                    total_data_mb=2048,
                    data_downloaded_mb=2048,
                ),
                DailyUsageMetrics(
                    user_id=test_user.id,
                    date=datetime(
                        period_start.year, period_start.month, period_start.day
                    ),
                    total_data_mb=1536,
                    data_downloaded_mb=1024,
                    data_uploaded_mb=512,
                ),
            ]
        )
        db.commit()

        plan_resp = client.get("/api/user/plan", headers=auth_headers)
        assert plan_resp.status_code == 200, plan_resp.text
        body = plan_resp.json()
        assert body["plan_tier"] == "premium"
        assert body["used_gb"] == 1.5

    def test_free_plan_cap_blocks_new_profile_after_usage_report(
        self, client, auth_headers, db, monkeypatch
    ):
        monkeypatch.setenv("FREE_TIER_MONTHLY_GB", "1")
        import services.subscription_access as subscription_access

        monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
        monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
        _create_free_server(db)

        profile_resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert profile_resp.status_code == 200, profile_resp.text
        device_id = profile_resp.json()["device_id"]

        report_resp = client.post(
            "/api/vpn/usage/report",
            json={
                "device_id": device_id,
                "protocol": "wireguard",
                "rx_bytes": 1024 * 1024 * 1024,
                "tx_bytes": 1,
            },
            headers=auth_headers,
        )
        assert report_resp.status_code == 200, report_resp.text

        blocked_resp = client.post(
            "/api/vpn/profile",
            json={
                "device_name": "Linux Box 2",
                "device_type": "linux",
                "protocol": "wireguard",
            },
            headers=auth_headers,
        )
        assert blocked_resp.status_code == 402, blocked_resp.text
        assert "Free plan limit reached" in blocked_resp.text

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
        assert "dev tun" in config
        assert "remote 10.0.0.9 1194" in config
        assert "redirect-gateway def1" in config
        assert "<ca>" in config
        assert "MIIBtest" in config
        assert "auth-user-pass" not in config
        assert "DEMO CONFIG" not in config

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
        assert "remote_addrs =" in config
        assert "secrets {" in config
        assert "auth = eap-mschapv2" in config
        assert "eap_id =" in config
        assert "secret =" in config
        assert "securewave-ikev2-ca.pem" in config
        assert "securewave-test-ikev2-secret" in config
