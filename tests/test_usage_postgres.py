"""Real row-lock and idempotency checks against a disposable PostgreSQL database."""
import os
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from sqlalchemy import create_engine
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

import test_vpn_client_owned_config as fixtures
from test_usage_recording import session, TOKEN
from services.usage_metering_service import UsageMeteringService
from models.wireguard_peer import WireGuardPeer


@pytest.fixture
def postgres_provisioning(monkeypatch):
    url = os.environ.get("SECUREWAVE_TEST_DATABASE_URL")
    if not url:
        pytest.skip("Disposable PostgreSQL URL not supplied")
    monkeypatch.setattr(fixtures, "create_engine", lambda *args, **kwargs: create_engine(url))
    generator = fixtures.provisioning.__wrapped__(monkeypatch)
    yield next(generator)
    try:
        next(generator)
    except StopIteration:
        pass


def test_concurrent_identical_checkpoints_count_once(postgres_provisioning):
    service, row = session(postgres_provisioning)
    row_id, device_id = row.id, row.device_id
    sessions = sessionmaker(bind=service.db.get_bind())
    barrier = Barrier(2)

    def report():
        with sessions() as db:
            barrier.wait(timeout=10)
            result = UsageMeteringService(db).checkpoint(
                connection_id=row_id, reporting_token=TOKEN, sequence=1,
                bytes_sent=5_000_000_000, bytes_received=7_000_000_000,
                final=False, reason="client_disconnect", stopped_at=None, verified=True, gap=False)
            return result.idempotent

    with ThreadPoolExecutor(2) as executor:
        futures = [executor.submit(report) for _ in range(2)]
        results = [future.result(timeout=20) for future in futures]
    assert sorted(results) == [False, True]
    service.db.expire_all()
    peer = service.db.query(WireGuardPeer).filter_by(id=device_id).one()
    assert (peer.total_data_sent, peer.total_data_received) == (5_000_000_000, 7_000_000_000)


def test_additive_migration_preserves_legacy_rows(postgres_provisioning):
    service, row = session(postgres_provisioning)
    database = service.db.get_bind()
    row_id = row.id
    service.db.close()
    with database.begin() as connection:
        for column in ("metering_version", "reporting_token_hash", "recording_quality",
                       "client_verified_at", "final_meter_sequence"):
            connection.execute(text("ALTER TABLE vpn_connections DROP COLUMN " + column))
        for column in ("server_transfer_rx", "server_transfer_tx", "server_snapshot_at"):
            connection.execute(text("ALTER TABLE wireguard_peers DROP COLUMN " + column))
        connection.execute(text("ALTER TABLE vpn_usage_events DROP COLUMN payload_digest"))
        connection.execute(text("ALTER TABLE wireguard_peers ALTER COLUMN total_data_sent TYPE INTEGER"))
        connection.execute(text("ALTER TABLE wireguard_peers ALTER COLUMN total_data_received TYPE INTEGER"))
    import scripts.migrate_usage_recording as migration
    migration.engine = database
    migration.migrate()
    migration.migrate()
    with database.connect() as connection:
        record = connection.execute(text("SELECT id,metering_version,recording_quality FROM vpn_connections")).one()
        assert tuple(record) == (row_id, 1, "legacy")
