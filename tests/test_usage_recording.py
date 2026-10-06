import asyncio
import hashlib
import importlib.util
from datetime import datetime
from pathlib import Path

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from test_vpn_client_owned_config import provisioning, _post_config, _public_key
from models.vpn_connection import VPNConnection
from models.vpn_usage_event import VPNUsageEvent
from models.wireguard_peer import WireGuardPeer
from routes.usage_recording import UsageCheckpoint, usage_checkpoint, usage_history
from services.usage_metering_service import (
    UsageMeteringService, UsageSequenceConflict, UsageSessionFinalized, UsageIdempotencyConflict,
)

TOKEN = "b" * 64


def session(provisioning, key="test-start-1"):
    response = _post_config(provisioning, {"public_key": _public_key(4)})
    service = UsageMeteringService(provisioning["db"])
    row = service.start_session(user_id=provisioning["user"].id,
        device_id=response.device_id, server_id=provisioning["server"].id,
        protocol="wireguard", idempotency_key=key, metering_version=2, reporting_token=TOKEN).connection
    return service, row


def checkpoint(service, row, sequence=1, sent=100, received=200, final=False, gap=False):
    return service.checkpoint(connection_id=row.id, reporting_token=TOKEN, sequence=sequence,
        bytes_sent=sent, bytes_received=received, final=final, reason="client_disconnect",
        stopped_at=row.connected_at if final else None, verified=True, gap=gap)


def test_cumulative_retry_lost_ack_and_large_totals(provisioning):
    service, row = session(provisioning)
    result = checkpoint(service, row, sent=5_000_000_000, received=7_000_000_000)
    assert not result.idempotent
    assert checkpoint(service, row, sent=5_000_000_000, received=7_000_000_000).idempotent
    checkpoint(service, row, sequence=5, sent=5_000_000_100, received=7_000_000_200, final=True)
    assert checkpoint(service, row, sequence=5, sent=5_000_000_100, received=7_000_000_200, final=True).idempotent
    peer = provisioning["db"].query(WireGuardPeer).filter_by(id=row.device_id).one()
    assert (peer.total_data_sent, peer.total_data_received) == (5_000_000_100, 7_000_000_200)
    assert peer.last_handshake_at is None  # Recording never invents a WireGuard handshake.
    assert row.recording_quality == "complete"
    assert provisioning["db"].query(VPNUsageEvent).count() == 2


def test_sequence_conflicts_and_terminal_immutability(provisioning):
    service, row = session(provisioning)
    checkpoint(service, row)
    with pytest.raises(UsageSequenceConflict):
        checkpoint(service, row, sequence=1, sent=101)
    with pytest.raises(UsageSequenceConflict):
        checkpoint(service, row, sequence=2, sent=99)
    checkpoint(service, row, sequence=2, sent=101, final=True)
    with pytest.raises(UsageSessionFinalized):
        checkpoint(service, row, sequence=3, sent=102)


def test_reconnect_accepts_old_recorders_final_tail(provisioning):
    service, first = session(provisioning)
    checkpoint(service, first)
    _, second = session(provisioning, "test-start-2")
    assert first.disconnected_at is None  # A new API request cannot end a real tunnel.
    checkpoint(service, first, sequence=2, sent=150, received=250, final=True)
    checkpoint(service, second, sent=10, received=20, final=True)
    peer = provisioning["db"].query(WireGuardPeer).filter_by(id=first.device_id).one()
    assert (peer.total_data_sent, peer.total_data_received) == (160, 270)


def test_token_hash_and_owner_isolation(provisioning):
    service, row = session(provisioning)
    assert row.reporting_token_hash == hashlib.sha256(TOKEN.encode()).hexdigest()
    assert row.reporting_token_hash != TOKEN
    result = asyncio.run(usage_history(provisioning["other_user"], provisioning["db"], 50, None))
    assert result["sessions"] == []
    with pytest.raises(HTTPException) as error:
        asyncio.run(usage_checkpoint(row.id, UsageCheckpoint(sequence=1, bytes_sent=100, bytes_received=200),
                                    "UsageSession " + "c" * 64, provisioning["db"]))
    assert error.value.status_code == 404
    with pytest.raises(UsageIdempotencyConflict):
        service.start_session(user_id=row.user_id, device_id=row.device_id, server_id=row.server_id,
            protocol="wireguard", idempotency_key="test-start-1", metering_version=2, reporting_token="c"*64)


def test_gap_is_permanent_and_history_is_paginated(provisioning):
    service, row = session(provisioning)
    checkpoint(service, row, gap=True)
    checkpoint(service, row, sequence=2, final=True)
    assert row.recording_quality == "gap"
    _, second = session(provisioning, "test-start-2")
    result = asyncio.run(usage_history(provisioning["user"], provisioning["db"], 1, None))
    assert result["sessions"][0]["session_id"] == second.id
    result = asyncio.run(usage_history(provisioning["user"], provisioning["db"], 1, result["next_cursor"]))
    assert result["sessions"][0]["session_id"] == row.id


@pytest.mark.parametrize("changes", [{"bytes_sent": -1}, {"bytes_sent": 2**63}, {"sequence": True},
                                     {"final": "true"}, {"destination": "example.com"}])
def test_invalid_checkpoints(changes):
    with pytest.raises(ValidationError):
        UsageCheckpoint.model_validate({"sequence": 1, "bytes_sent": 100, "bytes_received": 200, **changes})


def test_reporter_does_not_ack_wrong_session_or_missing_final():
    path = Path(__file__).parents[1] / "securewave_app/packaging/linux/securewave-usage-reporter.py"
    spec = importlib.util.spec_from_file_location("reporter", path)
    reporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reporter)
    import io, json
    class Response(io.BytesIO):
        pass
    record = {"session_id": 1, "token": TOKEN, "sequence": 2, "bytes_sent": 100,
              "bytes_received": 200, "final": True, "verified": True, "gap": False}
    for data in [{"session_id": 9, "last_sequence": 2, "bytes_sent": 100, "bytes_received": 200, "final_sequence": 2},
                 {"session_id": 1, "last_sequence": 2, "bytes_sent": 100, "bytes_received": 200}]:
        with pytest.raises(ValueError):
            reporter.submit(record, lambda *args, **kwargs: Response(json.dumps(data).encode()))
