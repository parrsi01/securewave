"""Request-boundary coverage for durable, owner-scoped VPN metering."""

from datetime import datetime
from unittest.mock import MagicMock

import pytest
from fastapi import status
from sqlalchemy.exc import IntegrityError

from models.user import User
from models.vpn_connection import VPNConnection
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.hashing_service import hash_password
from services.jwt_service import create_access_token
from services.usage_metering_service import (
    UsageActiveSessionConflict,
    UsageMeteringService,
)


def _server(db, *, server_id="metering-us-1"):
    observed_at = datetime.utcnow()
    server = VPNServer(
        server_id=server_id,
        location="New York",
        country="United States",
        country_code="US",
        city="New York",
        public_ip="203.0.113.91",
        endpoint="203.0.113.91:51820",
        wg_public_key="dGVzdC1ldGVyaW5nLXNlcnZlci1wdWJsaWMta2V5",
        wg_private_key_encrypted="encrypted-server-key",
        status="active",
        health_status="healthy",
        last_health_check=observed_at,
        protocol_runtime_evidence={
            "wireguard": {"healthy": True, "observed_at": observed_at.isoformat()}
        },
        hcloud_server_state="running",
        max_connections=100,
        current_connections=0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _peer(db, user, server, *, name="Metering Laptop", suffix="1"):
    peer = WireGuardPeer(
        user_id=user.id,
        server_id=server.id,
        public_key=f"metering-public-key-{suffix}",
        private_key_encrypted="encrypted-peer-key",
        ipv4_address=f"10.8.0.{20 + int(suffix)}/32",
        device_name=name,
        is_active=True,
        is_revoked=False,
    )
    db.add(peer)
    db.commit()
    db.refresh(peer)
    return peer


def _start(client, headers, peer, server, key="start-session-0001"):
    return client.post(
        "/api/vpn/usage/sessions/start",
        headers=headers,
        json={
            "device_id": peer.id,
            "server_id": server.server_id,
            "protocol": "wireguard",
            "idempotency_key": key,
        },
    )


def test_usage_session_is_idempotent_monotonic_and_finalized(client, db, test_user, auth_headers):
    server = _server(db)
    peer = _peer(db, test_user, server)

    started = _start(client, auth_headers, peer, server)
    assert started.status_code == status.HTTP_200_OK, started.text
    session_id = started.json()["session_id"]
    assert started.json()["status"] == "recorded"
    assert started.json()["idempotent"] is False

    repeated_start = _start(client, auth_headers, peer, server)
    assert repeated_start.status_code == status.HTTP_200_OK
    assert repeated_start.json()["session_id"] == session_id
    assert repeated_start.json()["idempotent"] is True

    increment = client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=auth_headers,
        json={"sequence": 1, "bytes_sent": 100, "bytes_received": 250, "idempotency_key": "increment-0001"},
    )
    assert increment.status_code == status.HTTP_200_OK, increment.text
    assert increment.json()["bytes_sent"] == 100
    assert increment.json()["bytes_received"] == 250

    repeated_increment = client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=auth_headers,
        json={"sequence": 1, "bytes_sent": 100, "bytes_received": 250, "idempotency_key": "increment-0001"},
    )
    assert repeated_increment.status_code == status.HTTP_200_OK
    assert repeated_increment.json()["idempotent"] is True
    assert repeated_increment.json()["bytes_sent"] == 100

    out_of_order = client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=auth_headers,
        json={"sequence": 1, "bytes_sent": 1, "bytes_received": 1, "idempotency_key": "increment-0002"},
    )
    assert out_of_order.status_code == status.HTTP_409_CONFLICT

    second_increment = client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=auth_headers,
        json={"sequence": 2, "bytes_sent": 50, "bytes_received": 75, "idempotency_key": "increment-0003"},
    )
    assert second_increment.status_code == status.HTTP_200_OK
    assert second_increment.json()["bytes_sent"] == 150
    assert second_increment.json()["bytes_received"] == 325

    finalized = client.post(
        f"/api/vpn/usage/sessions/{session_id}/disconnect",
        headers=auth_headers,
        json={"idempotency_key": "disconnect-0001", "reason": "client_disconnect"},
    )
    assert finalized.status_code == status.HTTP_200_OK
    assert finalized.json()["disconnected_at"]

    repeated_finalization = client.post(
        f"/api/vpn/usage/sessions/{session_id}/disconnect",
        headers=auth_headers,
        json={"idempotency_key": "disconnect-0001", "reason": "client_disconnect"},
    )
    assert repeated_finalization.status_code == status.HTTP_200_OK
    assert repeated_finalization.json()["idempotent"] is True

    after_finalization = client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=auth_headers,
        json={"sequence": 3, "bytes_sent": 1, "bytes_received": 1, "idempotency_key": "increment-0004"},
    )
    assert after_finalization.status_code == status.HTTP_409_CONFLICT

    db.refresh(peer)
    assert peer.total_data_sent == 150
    assert peer.total_data_received == 325


def test_reconnect_finalizes_old_session_and_login_persists_metering(client, db, test_user, auth_headers):
    server = _server(db, server_id="metering-us-2")
    peer = _peer(db, test_user, server, suffix="2")
    first = _start(client, auth_headers, peer, server, key="start-session-first")
    assert first.status_code == status.HTTP_200_OK
    first_id = first.json()["session_id"]

    second = _start(client, auth_headers, peer, server, key="start-session-second")
    assert second.status_code == status.HTTP_200_OK
    second_id = second.json()["session_id"]
    assert second_id != first_id

    previous = db.query(VPNConnection).filter(VPNConnection.id == first_id).one()
    assert previous.disconnected_at is not None
    assert previous.finalization_reason == "reconnect"

    # Logging out changes auth generation, but metering remains durable and is
    # available to the account after a new login.
    logout = client.post("/api/auth/logout", headers=auth_headers)
    assert logout.status_code == status.HTTP_200_OK
    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == status.HTTP_200_OK
    new_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    persisted_increment = client.post(
        f"/api/vpn/usage/sessions/{second_id}/increment",
        headers=new_headers,
        json={"sequence": 1, "bytes_sent": 3, "bytes_received": 4, "idempotency_key": "post-login-0001"},
    )
    assert persisted_increment.status_code == status.HTTP_200_OK
    assert persisted_increment.json()["bytes_sent"] == 3


def test_usage_session_isolated_between_accounts(client, db, test_user, auth_headers):
    server = _server(db, server_id="metering-us-3")
    peer = _peer(db, test_user, server, suffix="3")
    started = _start(client, auth_headers, peer, server, key="start-session-isolated")
    session_id = started.json()["session_id"]

    other = User(
        email="metering-other@example.com",
        hashed_password=hash_password("OtherPass123"),
        email_verified=True,
        is_active=True,
    )
    db.add(other)
    db.commit()
    other_headers = {"Authorization": f"Bearer {create_access_token(other)}"}

    assert client.post(
        f"/api/vpn/usage/sessions/{session_id}/increment",
        headers=other_headers,
        json={"sequence": 1, "bytes_sent": 1, "bytes_received": 1, "idempotency_key": "other-user-0001"},
    ).status_code == status.HTTP_404_NOT_FOUND
    assert _start(client, other_headers, peer, server, key="other-user-start").status_code == status.HTTP_404_NOT_FOUND


def test_usage_start_rejects_idempotency_payload_changes_and_server_mismatch(
    client, db, test_user, auth_headers
):
    assigned_server = _server(db, server_id="metering-assigned")
    other_server = _server(db, server_id="metering-other")
    peer = _peer(db, test_user, assigned_server, suffix="4")

    first = _start(
        client,
        auth_headers,
        peer,
        assigned_server,
        key="start-session-conflict",
    )
    assert first.status_code == status.HTTP_200_OK

    changed_payload = _start(
        client,
        auth_headers,
        peer,
        other_server,
        key="start-session-conflict",
    )
    assert changed_payload.status_code == status.HTTP_409_CONFLICT
    assert "idempotency" in changed_payload.text.lower()

    mismatched_assignment = _start(
        client,
        auth_headers,
        peer,
        other_server,
        key="start-session-mismatch",
    )
    assert mismatched_assignment.status_code == status.HTTP_409_CONFLICT
    assert "not assigned" in mismatched_assignment.text.lower()


def test_usage_start_does_not_acknowledge_a_different_concurrent_start_key():
    """The active-device unique race is a conflict, not an idempotent retry."""
    db = MagicMock()
    db.query.return_value.filter.return_value.first.side_effect = [
        None,
        MagicMock(server_id=7),
        None,
    ]
    db.commit.side_effect = IntegrityError("insert", {}, Exception("unique"))

    with pytest.raises(UsageActiveSessionConflict):
        UsageMeteringService(db).start_session(
            user_id=3,
            device_id=5,
            server_id=7,
            protocol="wireguard",
            idempotency_key="concurrent-start-key",
        )

    db.rollback.assert_called_once()
