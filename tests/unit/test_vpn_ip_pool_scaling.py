from datetime import datetime

import pytest
import ipaddress

from models.user import User
from services.hashing_service import hash_password
from services.vpn_peer_manager import VPNPeerManager


def _make_user(db, idx: int) -> User:
    user = User(
        email=f"ip-scaling-{idx}@example.com",
        hashed_password=hash_password("TestPass123"),
        email_verified=True,
        is_active=True,
        created_at=datetime.utcnow(),
        subscription_status="active",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_ip_pool_expands_across_multiple_22_blocks(db, monkeypatch):
    monkeypatch.setenv("WG_IP_POOL_BASE_CIDR", "10.200.0.0/22")
    monkeypatch.setenv("WG_IP_POOL_MAX_BLOCKS", "2")
    monkeypatch.setenv("WG_IP_POOL_RESERVED_HOSTS", "1020")  # 2 usable per /22

    manager = VPNPeerManager(db)
    ips = []
    for idx in range(1, 5):
        user = _make_user(db, idx)
        peer = manager.create_peer(user=user, server=None, device_name=f"dev-{idx}")
        ips.append(peer.ipv4_address)

    assert len(set(ips)) == 4
    first_block = ipaddress.ip_network("10.200.0.0/22")
    second_block = ipaddress.ip_network("10.200.4.0/22")
    ip_values = [ipaddress.ip_interface(raw).ip for raw in ips]
    assert any(ip in first_block for ip in ip_values)
    assert any(ip in second_block for ip in ip_values)


def test_ip_pool_exhaustion_raises_and_emits_alert(db, monkeypatch):
    monkeypatch.setenv("WG_IP_POOL_BASE_CIDR", "10.210.0.0/22")
    monkeypatch.setenv("WG_IP_POOL_MAX_BLOCKS", "1")
    monkeypatch.setenv("WG_IP_POOL_RESERVED_HOSTS", "1020")  # 2 usable total
    monkeypatch.setenv("WG_IP_EXHAUSTION_ALERT_PCT", "50")

    manager = VPNPeerManager(db)
    user1 = _make_user(db, 1)
    user2 = _make_user(db, 2)
    manager.create_peer(user=user1, server=None, device_name="a")
    manager.create_peer(user=user2, server=None, device_name="b")

    user3 = _make_user(db, 3)
    with pytest.raises(ValueError):
        manager.create_peer(user=user3, server=None, device_name="c")

    stats = manager.get_ip_pool_stats()
    assert stats["allocated"] == 2
    assert stats["capacity"] == 2
    assert stats["alert"] is not None
