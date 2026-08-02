"""WireGuard lifecycle contracts that must stay traffic-backed and local-safe."""

from datetime import datetime, timedelta


def _add_paid_subscription(db, user):
    from models.subscription import Subscription

    subscription = Subscription(
        user_id=user.id,
        plan_id="premium",
        plan_name="Premium",
        provider="stripe",
        status="active",
        current_period_end=datetime.utcnow() + timedelta(days=30),
    )
    db.add(subscription)
    db.commit()
    return subscription


def _add_peer(db, user, server):
    from models.wireguard_peer import WireGuardPeer

    peer = WireGuardPeer(
        user_id=user.id,
        server_id=server.id,
        public_key="lifecycle-peer-public-key",
        private_key_encrypted="lifecycle-peer-private-key",
        ipv4_address="10.8.0.10/32",
        total_data_sent=0,
        total_data_received=0,
    )
    db.add(peer)
    db.commit()
    db.refresh(peer)
    return peer


def test_paid_usage_and_plan_sync_remote_wireguard_counters(
    client, auth_headers, test_user, test_vpn_server, db, monkeypatch
):
    """API gauges must reflect server transfer counters, not stale DB zeros."""
    _add_paid_subscription(db, test_user)
    peer = _add_peer(db, test_user, test_vpn_server)

    class RecordingManager:
        async def list_peers(self, _connection):
            return True, [
                {
                    "public_key": peer.public_key,
                    "transfer_rx": 3 * 1024 * 1024,
                    "transfer_tx": 2 * 1024 * 1024,
                    "latest_handshake": 1_700_000_000,
                }
            ]

    import services.subscription_access as subscription_access

    monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
    monkeypatch.setattr(
        subscription_access,
        "get_wireguard_server_manager",
        lambda: RecordingManager(),
    )

    device_usage = client.get(
        f"/api/vpn/devices/{peer.id}/usage", headers=auth_headers
    )
    assert device_usage.status_code == 200, device_usage.text
    assert device_usage.json()["total_data_sent_mb"] == 2
    assert device_usage.json()["total_data_received_mb"] == 3

    usage = client.get("/api/vpn/usage", headers=auth_headers)
    assert usage.status_code == 200, usage.text
    assert usage.json()["total_data_sent_mb"] == 2
    assert usage.json()["total_data_received_mb"] == 3

    plan = client.get("/api/user/plan", headers=auth_headers)
    assert plan.status_code == 200, plan.text
    assert plan.json()["used_gb"] > 0


def test_compatibility_device_routes_do_not_touch_remote_manager_in_mock_mode(
    client, auth_headers, test_vpn_server, monkeypatch
):
    """Mock/demo lifecycle calls must not create or remove real server peers."""
    import routes.vpn as vpn_routes

    calls = []

    class RecordingManager:
        async def add_peer(self, *_args):
            calls.append("add")
            return True, "unexpected remote add"

        async def remove_peer(self, *_args):
            calls.append("remove")
            return True, "unexpected remote remove"

    monkeypatch.setattr(vpn_routes, "get_wireguard_server_manager", lambda: RecordingManager())

    created = client.post(
        "/api/vpn/create-device",
        headers=auth_headers,
        json={"name": "compat-lifecycle", "server_id": test_vpn_server.server_id},
    )
    assert created.status_code == 200, created.text
    device_id = created.json()["device_id"]
    assert calls == []

    revoked = client.post(
        "/api/vpn/revoke-device",
        headers=auth_headers,
        json={"device_id": device_id},
    )
    assert revoked.status_code == 200, revoked.text
    assert calls == []


def test_device_create_does_not_touch_remote_manager_in_mock_mode(
    client, auth_headers, test_vpn_server, monkeypatch
):
    import routes.devices as device_routes

    calls = []

    class RecordingManager:
        async def add_peer(self, *_args):
            calls.append("add")
            return True, "unexpected remote add"

    monkeypatch.setattr(
        device_routes, "get_wireguard_server_manager", lambda: RecordingManager()
    )

    created = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={"name": "direct-lifecycle", "server_id": test_vpn_server.server_id},
    )
    assert created.status_code == 201, created.text
    assert calls == []


def test_live_profile_fails_closed_when_wireguard_peer_registration_fails(
    client, auth_headers, db, monkeypatch
):
    from models.wireguard_peer import WireGuardPeer
    from tests.integration.test_vpn_profile import _create_free_server

    server = _create_free_server(db, server_id="lifecycle-registration-failure")

    class FailingManager:
        async def add_peer(self, *_args):
            return False, "server rejected peer"

    import routes.vpn as vpn_routes

    monkeypatch.setattr(vpn_routes, "DEMO_MODE", False)
    monkeypatch.setattr(vpn_routes, "WG_MOCK_MODE", False)
    monkeypatch.setattr(vpn_routes, "AUTO_REGISTER_PEERS", True)
    monkeypatch.setattr(vpn_routes, "_remote_peer_sync_enabled", lambda: True)
    monkeypatch.setattr(vpn_routes, "get_wireguard_server_manager", lambda: FailingManager())

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "registration-failure-device",
            "device_type": "linux",
            "server_id": server.server_id,
        },
    )

    assert response.status_code == 503, response.text
    assert "peer registration failed" in response.text.lower()
    assert (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.device_name == "registration-failure-device",
            WireGuardPeer.is_revoked == False,
        )
        .count()
        == 0
    )


def test_live_device_revoke_does_not_hide_remote_peer_removal_failure(
    client, auth_headers, test_user, test_vpn_server, db, monkeypatch
):
    from models.wireguard_peer import WireGuardPeer

    peer = _add_peer(db, test_user, test_vpn_server)

    class FailingManager:
        async def remove_peer(self, *_args):
            return False, "server unavailable"

    import routes.devices as device_routes

    monkeypatch.setattr(device_routes, "_remote_peer_sync_enabled", lambda: True)
    monkeypatch.setattr(
        device_routes, "get_wireguard_server_manager", lambda: FailingManager()
    )

    response = client.delete(
        f"/api/vpn/devices/{peer.id}",
        headers=auth_headers,
    )

    assert response.status_code == 503, response.text
    db.refresh(peer)
    assert peer.is_revoked is False
    assert db.query(WireGuardPeer).filter(WireGuardPeer.id == peer.id).count() == 1
