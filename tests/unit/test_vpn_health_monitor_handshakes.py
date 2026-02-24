from datetime import datetime, timedelta

import pytest

from models.user import User
from models.wireguard_peer import WireGuardPeer
from services.hashing_service import hash_password
from services.vpn_health_monitor import VPNHealthMonitor
from services.wireguard_service import WireGuardService


class _StubManager:
    def __init__(self, latest_handshake: int | None):
        self.latest_handshake = latest_handshake

    async def list_peers(self, conn):
        return True, [
            {
                "public_key": "stub-public-key",
                "latest_handshake": self.latest_handshake,
                "transfer_rx": 123,
                "transfer_tx": 456,
            }
        ]


@pytest.mark.asyncio
async def test_stale_handshake_marks_peer_unstable(db, test_vpn_server, monkeypatch):
    user = User(
        email="stale-handshake@example.com",
        hashed_password=hash_password("TestPass123"),
        email_verified=True,
        is_active=True,
        created_at=datetime.utcnow(),
        subscription_status="active",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    wg_service = WireGuardService()
    private_key, _ = wg_service.generate_keypair()
    peer = WireGuardPeer(
        user_id=user.id,
        server_id=test_vpn_server.id,
        public_key="stub-public-key",
        private_key_encrypted=wg_service.encrypt_private_key(private_key),
        ipv4_address="10.250.0.10/32",
        is_active=True,
        is_revoked=False,
        last_handshake_at=datetime.utcnow() - timedelta(hours=2),
    )
    db.add(peer)
    db.commit()

    stale_epoch = int((datetime.utcnow() - timedelta(minutes=30)).timestamp())
    monkeypatch.setattr("services.vpn_health_monitor.get_wireguard_server_manager", lambda: _StubManager(stale_epoch))

    monitor = VPNHealthMonitor()
    monitor.db = db
    await monitor.refresh_peer_handshake_health(test_vpn_server)

    db.refresh(peer)
    db.refresh(test_vpn_server)

    assert peer.health_status == "unstable"
    assert test_vpn_server.health_status in {"degraded", "unstable"}


def test_handshake_classification_thresholds():
    assert VPNHealthMonitor.classify_handshake_freshness(10) == "healthy"
    assert VPNHealthMonitor.classify_handshake_freshness(180) == "degraded"
    assert VPNHealthMonitor.classify_handshake_freshness(360) == "unstable"
    assert VPNHealthMonitor.classify_handshake_freshness(None) == "pending"


def test_pending_peers_do_not_degrade_server_health():
    """Peers that have never connected should not drag server health down."""
    # All pending -- server is idle, should be healthy
    assert VPNHealthMonitor.classify_server_health(["pending"]) == "healthy"
    assert VPNHealthMonitor.classify_server_health(["pending", "pending"]) == "healthy"

    # Mix of pending and healthy -- only healthy peers count
    assert VPNHealthMonitor.classify_server_health(["pending", "healthy"]) == "healthy"

    # One real unstable peer among pending ones -- unstable ratio = 1/1 = 100%
    assert VPNHealthMonitor.classify_server_health(["pending", "unstable"]) == "unstable"
