"""Opt-in PostgreSQL proof for metering's row-level race handling."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import os
import uuid

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


POSTGRES_URL = os.getenv("SECUREWAVE_TEST_POSTGRES_URL")
pytestmark = pytest.mark.integration


@pytest.mark.skipif(not POSTGRES_URL, reason="SECUREWAVE_TEST_POSTGRES_URL is required for PostgreSQL concurrency coverage")
def test_postgres_concurrent_usage_sequence_has_single_winner():
    from models.user import User
    from models.subscription import Subscription  # noqa: F401 - mapper registration
    from models.vpn_connection import VPNConnection
    from models.vpn_server import VPNServer
    from models.vpn_usage_event import VPNUsageEvent
    from models.wireguard_peer import WireGuardPeer
    from services.hashing_service import hash_password
    from services.usage_metering_service import UsageMeteringService, UsageSequenceConflict

    engine = create_engine(POSTGRES_URL, pool_pre_ping=True)
    sessions = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    suffix = uuid.uuid4().hex[:12]
    seed = sessions()
    try:
        user = User(
            email=f"metering-race-{suffix}@example.com",
            hashed_password=hash_password("RacePass123"),
            email_verified=True,
            is_active=True,
        )
        seed.add(user)
        seed.flush()
        server = VPNServer(
            server_id=f"race-{suffix}",
            location="Race city",
            country="Testland",
            country_code="TS",
            city="Race city",
            public_ip="203.0.113.199",
            endpoint="203.0.113.199:51820",
            wg_public_key=f"race-server-key-{suffix}",
            wg_private_key_encrypted="encrypted-server-key",
            status="active",
            health_status="healthy",
            last_health_check=datetime.utcnow(),
            hcloud_server_state="running",
            max_connections=10,
        )
        seed.add(server)
        seed.flush()
        peer = WireGuardPeer(
            user_id=user.id,
            server_id=server.id,
            public_key=f"race-peer-key-{suffix}",
            private_key_encrypted="encrypted-peer-key",
            ipv4_address=f"10.8.{int(suffix[:2], 16) % 200 + 20}.{int(suffix[2:4], 16) % 200 + 20}/32",
            device_name=f"Race device {suffix}",
            is_active=True,
            is_revoked=False,
        )
        seed.add(peer)
        seed.commit()
        user_id, server_id, peer_id = user.id, server.id, peer.id

        starter = sessions()
        try:
            connection_id = UsageMeteringService(starter).start_session(
                user_id=user_id,
                device_id=peer_id,
                server_id=server_id,
                protocol="wireguard",
                idempotency_key=f"start-{suffix}",
            ).connection.id
        finally:
            starter.close()

        def increment(key: str):
            db = sessions()
            try:
                try:
                    UsageMeteringService(db).increment(
                        user_id=user_id,
                        connection_id=connection_id,
                        sequence=1,
                        bytes_sent=11,
                        bytes_received=13,
                        idempotency_key=key,
                    )
                    return "applied"
                except UsageSequenceConflict:
                    return "sequence_conflict"
            finally:
                db.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(increment, [f"event-a-{suffix}", f"event-b-{suffix}"]))
        assert sorted(outcomes) == ["applied", "sequence_conflict"]

        verify = sessions()
        try:
            connection = verify.query(VPNConnection).filter(VPNConnection.id == connection_id).one()
            assert connection.total_bytes_sent == 11
            assert connection.total_bytes_received == 13
            assert verify.query(VPNUsageEvent).filter(VPNUsageEvent.connection_id == connection_id).count() == 1
        finally:
            verify.close()
    finally:
        cleanup = sessions()
        try:
            if 'connection_id' in locals():
                cleanup.query(VPNUsageEvent).filter(VPNUsageEvent.connection_id == connection_id).delete()
                cleanup.query(VPNConnection).filter(VPNConnection.id == connection_id).delete()
            if 'peer_id' in locals():
                cleanup.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).delete()
            if 'server_id' in locals():
                cleanup.query(VPNServer).filter(VPNServer.id == server_id).delete()
            if 'user_id' in locals():
                cleanup.query(User).filter(User.id == user_id).delete()
            cleanup.commit()
        finally:
            cleanup.close()


@pytest.mark.skipif(not POSTGRES_URL, reason="SECUREWAVE_TEST_POSTGRES_URL is required for PostgreSQL concurrency coverage")
def test_postgres_concurrent_peer_issuance_reuses_device_and_keeps_keys_and_ips_unique():
    """The profile peer allocator must serialize retries and distinct devices."""
    from models.user import User
    from models.wireguard_peer import WireGuardPeer
    from services.hashing_service import hash_password
    from services.vpn_peer_manager import VPNPeerManager

    engine = create_engine(POSTGRES_URL, pool_pre_ping=True)
    sessions = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    suffix = uuid.uuid4().hex[:12]
    peer_ids: set[int] = set()
    user_id = None

    seed = sessions()
    try:
        user = User(
            email=f"peer-race-{suffix}@example.com",
            hashed_password=hash_password("RacePass123"),
            email_verified=True,
            is_active=True,
        )
        seed.add(user)
        seed.commit()
        user_id = user.id

        def create_peer(device_name: str):
            db = sessions()
            try:
                current_user = db.get(User, user_id)
                assert current_user is not None
                peer = VPNPeerManager(db).create_peer(
                    current_user,
                    device_name=device_name,
                    max_active_devices=4,
                    reuse_existing_device=True,
                )
                return peer.id, peer.public_key, peer.ipv4_address
            finally:
                db.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            duplicate_request_results = list(
                pool.map(create_peer, ["Primary Linux", "Primary Linux"])
            )
        assert duplicate_request_results[0] == duplicate_request_results[1]
        peer_ids.add(duplicate_request_results[0][0])

        with ThreadPoolExecutor(max_workers=2) as pool:
            distinct_device_results = list(
                pool.map(create_peer, ["Laptop A", "Laptop B"])
            )
        peer_ids.update(result[0] for result in distinct_device_results)
        assert len({result[1] for result in distinct_device_results}) == 2
        assert len({result[2] for result in distinct_device_results}) == 2
        assert distinct_device_results[0][2] != duplicate_request_results[0][2]
        assert distinct_device_results[1][2] != duplicate_request_results[0][2]
    finally:
        cleanup = sessions()
        try:
            if peer_ids:
                cleanup.query(WireGuardPeer).filter(WireGuardPeer.id.in_(peer_ids)).delete(
                    synchronize_session=False
                )
            if user_id is not None:
                cleanup.query(User).filter(User.id == user_id).delete()
            cleanup.commit()
        finally:
            cleanup.close()
