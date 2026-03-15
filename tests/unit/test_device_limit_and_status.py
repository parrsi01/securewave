"""
Unit tests for device limit logic, deletion reducing active count,
and /vpn/status schema correctness.
"""

import pytest
from datetime import datetime, timedelta


# ---------------------------------------------------------------------------
# Device limit logic (pure function, no HTTP)
# ---------------------------------------------------------------------------

class TestDeviceLimitLogic:
    """Verify get_device_limit returns correct limits per tier."""

    def test_free_user_limit(self, db, free_user):
        from routes.devices import get_device_limit
        assert get_device_limit(free_user, db) == 1

    def test_premium_user_limit(self, db, premium_user):
        from routes.devices import get_device_limit
        assert get_device_limit(premium_user, db) == 5

    def test_no_subscription_defaults_to_free(self, db, test_user):
        from routes.devices import get_device_limit
        assert get_device_limit(test_user, db) == 1


# ---------------------------------------------------------------------------
# Device deletion reduces active count
# ---------------------------------------------------------------------------

class TestDeviceDeletionReducesCount:
    """Verify that revoking a device reduces the active peer count."""

    def test_revoke_reduces_active_count(self, db, free_user, test_vpn_server):
        from models.wireguard_peer import WireGuardPeer
        from services.vpn_peer_manager import get_peer_manager

        peer_manager = get_peer_manager(db)
        peer = peer_manager.create_peer(
            user=free_user,
            server=test_vpn_server,
            device_name="test-device-1",
            device_type="linux",
        )

        # Active count should be 1
        active = db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == free_user.id,
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.is_active == True,
        ).count()
        assert active == 1

        # Revoke
        peer_manager.revoke_peer(peer.id)
        db.refresh(peer)
        assert peer.device_state == "revoked"

        # Active count should be 0
        active_after = db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == free_user.id,
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.is_active == True,
        ).count()
        assert active_after == 0

    def test_revoked_peer_not_counted_toward_limit(self, db, free_user, test_vpn_server):
        from models.wireguard_peer import WireGuardPeer
        from services.vpn_peer_manager import get_peer_manager

        peer_manager = get_peer_manager(db)
        peer = peer_manager.create_peer(
            user=free_user,
            server=test_vpn_server,
            device_name="device-a",
            device_type="linux",
        )
        peer_manager.revoke_peer(peer.id)

        # Should be able to create another (limit=1, active=0 after revoke)
        peer2 = peer_manager.create_peer(
            user=free_user,
            server=test_vpn_server,
            device_name="device-b",
            device_type="linux",
        )
        assert peer2 is not None
        assert peer2.is_active is True
        assert peer2.is_revoked is False
        assert peer2.device_state == "active"

    def test_cleanup_job_marks_expired_devices(self, db, free_user, test_vpn_server):
        from services.device_service import get_device_service
        from services.vpn_peer_manager import get_peer_manager

        peer_manager = get_peer_manager(db)
        peer = peer_manager.create_peer(
            user=free_user,
            server=test_vpn_server,
            device_name="stale-device",
            device_type="linux",
        )
        peer.profile_expires_at = datetime.utcnow() - timedelta(minutes=10)
        db.add(peer)
        db.commit()

        summary = get_device_service(db).expire_due_devices()
        assert summary.expired == 1

        db.refresh(peer)
        assert peer.device_state == "expired"
        assert peer.is_active is False
        assert peer.is_revoked is False


# ---------------------------------------------------------------------------
# /vpn/status schema correctness
# ---------------------------------------------------------------------------

class TestStatusEndpointSchema:
    """Verify ConnectionStatusResponse has all required fields."""

    def test_status_response_model_fields(self):
        from routes.vpn import ConnectionStatusResponse

        # Verify the model has all required fields
        fields = ConnectionStatusResponse.model_fields
        assert "status" in fields
        assert "connected" in fields
        assert "server_id" in fields
        assert "server_location" in fields
        assert "client_ip" in fields
        assert "connected_since" in fields
        assert "bytes_sent" in fields
        assert "bytes_received" in fields

    def test_disconnected_status_serialization(self):
        from routes.vpn import ConnectionStatusResponse

        resp = ConnectionStatusResponse(status="DISCONNECTED", connected=False)
        data = resp.model_dump()
        assert data["connected"] is False
        assert data["status"] == "DISCONNECTED"
        assert data["bytes_sent"] is None
        assert data["bytes_received"] is None

    def test_connected_status_serialization(self):
        from routes.vpn import ConnectionStatusResponse

        resp = ConnectionStatusResponse(
            status="CONNECTED",
            connected=True,
            server_id="us-east-1-001",
            server_location="New York, United States",
            client_ip="10.8.0.2",
            connected_since="2026-03-01T12:00:00",
            bytes_sent=1024,
            bytes_received=2048,
        )
        data = resp.model_dump()
        assert data["connected"] is True
        assert data["bytes_sent"] == 1024
        assert data["bytes_received"] == 2048
        assert data["server_id"] == "us-east-1-001"


# ---------------------------------------------------------------------------
# ServerInfo schema includes latency_priority
# ---------------------------------------------------------------------------

class TestServerInfoSchema:
    """Verify ServerInfo includes latency_priority for Flutter alignment."""

    def test_server_info_has_latency_priority(self):
        from routes.vpn import ServerInfo

        fields = ServerInfo.model_fields
        assert "latency_priority" in fields

    def test_server_info_latency_priority_serializes(self):
        from routes.vpn import ServerInfo

        info = ServerInfo(
            server_id="test-1",
            location="Test",
            country="US",
            country_code="US",
            city="Test City",
            status="active",
            health_status="healthy",
            latency_priority=100,
        )
        data = info.model_dump()
        assert data["latency_priority"] == 100
