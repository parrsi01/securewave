from __future__ import annotations

from datetime import datetime

import pytest

from models.usage_analytics import DailyUsageMetrics, UserUsageStats
from models.vpn_connection import VPNConnection
from models.wireguard_peer import WireGuardPeer
from tools.admin.reset_usage_and_devices import ResetSafetyError, reset_usage_and_devices


def test_reset_usage_and_devices_requires_explicit_guard(db, monkeypatch, capsys):
    monkeypatch.delenv("SECUREWAVE_ALLOW_DEV_RESETS", raising=False)
    monkeypatch.setenv("ENVIRONMENT", "development")
    with pytest.raises(ResetSafetyError):
        reset_usage_and_devices(db=db, dry_run=True)
    captured = capsys.readouterr()
    assert "dev_reset_denied" in captured.err
    assert "missing_allow_flag" in captured.err


def test_reset_usage_and_devices_logs_denied_in_production(db, monkeypatch, capsys):
    monkeypatch.setenv("SECUREWAVE_ALLOW_DEV_RESETS", "1")
    monkeypatch.setenv("ENVIRONMENT", "production")
    with pytest.raises(ResetSafetyError):
        reset_usage_and_devices(db=db, dry_run=True)
    captured = capsys.readouterr()
    assert "dev_reset_denied" in captured.err
    assert "production_environment" in captured.err


def test_reset_usage_and_devices_zeroes_usage_and_revokes_devices(
    db,
    monkeypatch,
    free_user,
    test_vpn_server,
):
    peer = WireGuardPeer(
        user_id=free_user.id,
        server_id=test_vpn_server.id,
        public_key="test-reset-public-key-001",
        private_key_encrypted="encrypted-key",
        ipv4_address="10.8.0.66/32",
        is_active=True,
        is_revoked=False,
        total_data_sent=123456,
        total_data_received=654321,
        connection_count=7,
    )
    connection = VPNConnection(
        user_id=free_user.id,
        server_id=test_vpn_server.id,
        client_ip="10.8.0.66",
        connected_at=datetime.utcnow(),
        disconnected_at=None,
        total_bytes_sent=111,
        total_bytes_received=222,
    )
    usage = UserUsageStats(
        user_id=free_user.id,
        total_connections=5,
        active_connections=1,
        total_bytes_uploaded=2048,
        total_bytes_downloaded=4096,
        total_data_gb=1.2,
        current_month_data_gb=0.8,
    )
    daily = DailyUsageMetrics(
        user_id=free_user.id,
        date=datetime.utcnow(),
        connections_count=2,
        total_connection_time_seconds=300,
        data_uploaded_mb=10.5,
        data_downloaded_mb=20.5,
        total_data_mb=31.0,
        connection_failures=1,
    )
    db.add_all([peer, connection, usage, daily])
    db.commit()

    monkeypatch.setenv("SECUREWAVE_ALLOW_DEV_RESETS", "1")
    monkeypatch.setenv("ENVIRONMENT", "development")
    summary = reset_usage_and_devices(db=db)

    db.refresh(peer)
    db.refresh(connection)
    db.refresh(usage)
    db.refresh(daily)

    assert summary.peers_updated >= 1
    assert summary.connections_updated >= 1
    assert summary.usage_rows_updated >= 1
    assert summary.daily_rows_updated >= 1

    assert peer.total_data_sent == 0
    assert peer.total_data_received == 0
    assert peer.connection_count == 0
    assert peer.is_active is False
    assert peer.is_revoked is True

    assert connection.total_bytes_sent == 0
    assert connection.total_bytes_received == 0
    assert connection.disconnected_at is not None

    assert usage.total_bytes_uploaded == 0
    assert usage.total_bytes_downloaded == 0
    assert usage.total_data_gb == 0.0
    assert usage.current_month_data_gb == 0.0
    assert usage.active_connections == 0

    assert daily.total_data_mb == 0.0
    assert daily.data_uploaded_mb == 0.0
    assert daily.data_downloaded_mb == 0.0
    assert daily.connections_count == 0
