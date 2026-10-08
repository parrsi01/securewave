"""Monthly accounting, isolation, rollover and existing quota entry points."""
import asyncio
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from database.session import get_db
from models.subscription import Subscription
from models.vpn_usage_event import VPNUsageEvent
from models.wireguard_peer import WireGuardPeer
from routes.usage_recording import router
from services.jwt_service import get_current_user
from services.monthly_usage import FREE_MONTHLY_BYTES, month_bounds, monthly_summary, monthly_totals
from services.subscription_access import enforce_free_tier_cap, is_free_tier, require_active_subscription
from test_usage_recording import session, checkpoint
from test_vpn_client_owned_config import provisioning


def stamp(db, row, sequence, at):
    db.query(VPNUsageEvent).filter_by(connection_id=row.id, sequence=sequence).one().created_at = at
    db.commit()


def test_new_free_account_and_http_owner_scope(provisioning):
    p = provisioning
    summary = monthly_summary(p['db'], p['user'])
    assert summary['plan_id'] == 'free'
    assert summary['quota_bytes'] == FREE_MONTHLY_BYTES == 5_000_000_000
    assert summary['used_bytes'] == 0
    assert summary['last_session'] is None
    app = FastAPI()
    app.include_router(router, prefix='/vpn')
    app.dependency_overrides[get_db] = lambda: p['db']
    client = TestClient(app)
    assert client.get('/vpn/usage/monthly').status_code == 401
    app.dependency_overrides[get_current_user] = lambda: p['user']
    assert client.get('/vpn/usage/monthly').json()['user_id'] == p['user'].id
    assert client.get('/vpn/usage/monthly', params=[('session_ids', i) for i in range(101)]).status_code == 422


def test_exactly_once_cumulative_multiple_sessions_and_revoked_peer(provisioning):
    service, first = session(provisioning)
    checkpoint(service, first, sent=100, received=200)
    checkpoint(service, first, sent=100, received=200)  # Retry, no extra charge.
    checkpoint(service, first, sequence=2, sent=150, received=250, final=True)
    _, second = session(provisioning, 'reconnect-monthly')
    checkpoint(service, second, sent=100, received=260570, final=True)
    db = provisioning['db']
    peer = db.query(WireGuardPeer).filter_by(id=first.device_id).one()
    peer.is_revoked = True
    peer.server_transfer_rx = 10_000_000_000  # Not billed again.
    db.commit()
    result = monthly_summary(db, provisioning['user'], [first.id, second.id])
    assert result['used_bytes'] == 261070
    assert result['bytes_sent'] == 250
    assert result['bytes_received'] == 260820
    assert result['last_session']['session_id'] == second.id
    assert len(result['tracked_sessions']) == 2
    # A subsequent request/login reads the same durable total, no UI session required.
    db.expire_all()
    assert monthly_summary(db, provisioning['user'])['used_bytes'] == 261070
    other = monthly_summary(db, provisioning['other_user'], [first.id, second.id])
    assert other['used_bytes'] == 0
    assert other['tracked_sessions'] == []
    assert other['last_session'] is None


def test_cross_month_checkpoint_differences_and_year_rollover(provisioning):
    db = provisioning['db']
    service, row = session(provisioning)
    checkpoint(service, row, sent=100, received=200)
    stamp(db, row, 1, datetime(2026, 12, 31, 23, 59, 59))
    checkpoint(service, row, sequence=2, sent=130, received=250)
    stamp(db, row, 2, datetime(2027, 1, 1))
    checkpoint(service, row, sequence=3, sent=150, received=270, final=True)
    stamp(db, row, 3, datetime(2027, 1, 2))
    assert monthly_totals(db, row.user_id, datetime(2026, 12, 20)) == (100, 200)
    assert monthly_totals(db, row.user_id, datetime(2027, 1, 20)) == (50, 70)
    assert monthly_totals(db, row.user_id, datetime(2027, 2, 20)) == (0, 0)
    start, end = month_bounds(datetime(2026, 12, 31, tzinfo=timezone.utc))
    assert start == datetime(2026, 12, 1) and end == datetime(2027, 1, 1)


def test_legacy_increment_events_are_added_not_maximized(provisioning):
    db = provisioning['db']
    service, row = session(provisioning)
    row.metering_version = 1
    db.commit()
    for sequence, sent, received in [(1, 100, 200), (2, 30, 50)]:
        service.increment(user_id=row.user_id, connection_id=row.id,
                          sequence=sequence, bytes_sent=sent, bytes_received=received,
                          idempotency_key=f'legacy-month-{sequence}')
    assert monthly_totals(db, row.user_id) == (130, 250)


def test_limit_can_be_read_finalized_and_renews_next_month(provisioning, monkeypatch):
    db = provisioning['db']
    service, row = session(provisioning)
    checkpoint(service, row, sent=1, received=FREE_MONTHLY_BYTES - 1)
    with pytest.raises(HTTPException) as error:
        asyncio.run(enforce_free_tier_cap(db, provisioning['user']))
    assert error.value.status_code == 402
    assert monthly_summary(db, provisioning['user'])['limit_reached'] is True
    checkpoint(service, row, sequence=2, sent=2, received=FREE_MONTHLY_BYTES, final=True)
    peer = db.query(WireGuardPeer).filter_by(id=row.device_id).one()
    assert not peer.is_revoked  # A quota read must not delete peer configuration.
    for event in db.query(VPNUsageEvent).all():
        event.created_at = datetime(2020, 1, 1)
    db.commit()
    assert monthly_summary(db, provisioning['user'])['used_bytes'] == 0
    asyncio.run(enforce_free_tier_cap(db, provisioning['user']))


def test_active_free_subscription_cannot_bypass_free_quota(provisioning):
    db = provisioning['db']
    user = provisioning['user']
    db.add(Subscription(user_id=user.id, plan_id='free', plan_name='Free', status='active'))
    db.commit()
    assert is_free_tier(db, user)
    service, row = session(provisioning)
    checkpoint(service, row, received=FREE_MONTHLY_BYTES)
    with pytest.raises(HTTPException) as error:
        asyncio.run(require_active_subscription(db, user))
    assert error.value.status_code == 402
