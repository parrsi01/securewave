#!/usr/bin/env python3
"""
Reset usage counters and device allocations in DEV/TEST only.

Safety requirements:
- Requires SECUREWAVE_ALLOW_DEV_RESETS=1
- Refuses production environments
- Optional DB backup before mutation
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sqlalchemy.orm import Session

from database.session import DATABASE_URL, SessionLocal
from models.usage_analytics import DailyUsageMetrics, UserUsageStats
from models.vpn_connection import VPNConnection
from models.wireguard_peer import WireGuardPeer
from utils.env_validation import is_production, is_testing


BACKUP_DIR = REPO_ROOT / "backups"


class ResetSafetyError(RuntimeError):
    pass


@dataclass(frozen=True)
class ResetSummary:
    peers_updated: int
    connections_updated: int
    usage_rows_updated: int
    daily_rows_updated: int
    backup_path: Optional[str] = None


def _require_dev_reset_guard() -> None:
    allow = os.getenv("SECUREWAVE_ALLOW_DEV_RESETS", "").strip() == "1"
    if not allow:
        print(
            {
                "event": "dev_reset_denied",
                "reason": "missing_allow_flag",
                "environment": os.getenv("ENVIRONMENT", "development"),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
            file=sys.stderr,
        )
        raise ResetSafetyError("SECUREWAVE_ALLOW_DEV_RESETS=1 is required")
    if is_production():
        print(
            {
                "event": "dev_reset_denied",
                "reason": "production_environment",
                "environment": os.getenv("ENVIRONMENT", "development"),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
            file=sys.stderr,
        )
        raise ResetSafetyError("Refusing reset in production environment")


def _timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def _sqlite_path_from_url(database_url: str) -> Optional[Path]:
    if not database_url.startswith("sqlite:///"):
        return None
    raw = database_url.replace("sqlite:///", "", 1)
    if raw == ":memory:":
        return None
    path = Path(raw)
    if not path.is_absolute():
        path = (REPO_ROOT / raw).resolve()
    return path


def create_backup() -> Optional[Path]:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = _timestamp()
    sqlite_path = _sqlite_path_from_url(DATABASE_URL)
    if sqlite_path:
        if not sqlite_path.exists():
            return None
        dst = BACKUP_DIR / f"db_pre_sim_{stamp}.sqlite"
        shutil.copy2(sqlite_path, dst)
        return dst

    if DATABASE_URL.startswith("postgresql"):
        dst = BACKUP_DIR / f"db_pre_sim_{stamp}.dump"
        result = subprocess.run(  # nosec B603
            ["pg_dump", DATABASE_URL, "-Fc", "-f", str(dst)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise ResetSafetyError(f"pg_dump failed: {result.stderr.strip()}")
        return dst
    return None


def reset_usage_and_devices(db: Optional[Session] = None, *, dry_run: bool = False) -> ResetSummary:
    _require_dev_reset_guard()
    owns_session = db is None
    session = db or SessionLocal()
    now = datetime.now(timezone.utc)

    try:
        peers = session.query(WireGuardPeer).all()
        for peer in peers:
            peer.total_data_sent = 0
            peer.total_data_received = 0
            peer.connection_count = 0
            peer.is_active = False
            if not peer.is_revoked:
                peer.is_revoked = True
                peer.revoked_at = now
            session.add(peer)

        connections = session.query(VPNConnection).all()
        for conn in connections:
            conn.total_bytes_sent = 0
            conn.total_bytes_received = 0
            if conn.disconnected_at is None:
                conn.disconnected_at = now
            session.add(conn)

        usage_rows = session.query(UserUsageStats).all()
        for row in usage_rows:
            row.total_connections = 0
            row.active_connections = 0
            row.total_connection_time_seconds = 0
            row.average_session_duration_seconds = 0
            row.total_bytes_uploaded = 0
            row.total_bytes_downloaded = 0
            row.total_data_gb = 0.0
            row.current_month_data_gb = 0.0
            row.total_server_switches = 0
            row.unique_servers_used = 0
            row.last_connection_at = None
            row.last_activity_at = now
            row.updated_at = now
            session.add(row)

        daily_rows = session.query(DailyUsageMetrics).all()
        for row in daily_rows:
            row.connections_count = 0
            row.total_connection_time_seconds = 0
            row.data_uploaded_mb = 0.0
            row.data_downloaded_mb = 0.0
            row.total_data_mb = 0.0
            row.connection_failures = 0
            session.add(row)

        if dry_run:
            session.rollback()
        else:
            session.commit()

        return ResetSummary(
            peers_updated=len(peers),
            connections_updated=len(connections),
            usage_rows_updated=len(usage_rows),
            daily_rows_updated=len(daily_rows),
            backup_path=None,
        )
    finally:
        if owns_session:
            session.close()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Reset usage/devices for dev/test SecureWave DB.")
    parser.add_argument("--yes", action="store_true", help="Execute reset (required).")
    parser.add_argument("--dry-run", action="store_true", help="Do not persist changes.")
    parser.add_argument("--with-backup", action="store_true", help="Create DB snapshot before reset.")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if not args.yes:
        print("Refusing to run without --yes", file=sys.stderr)
        return 2
    try:
        backup_path = create_backup() if args.with_backup else None
        summary = reset_usage_and_devices(dry_run=args.dry_run)
    except ResetSafetyError as exc:
        print(f"reset_aborted: {exc}", file=sys.stderr)
        return 3

    payload = {
        "status": "ok",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "testing": is_testing(),
        "database_driver": DATABASE_URL.split("://", 1)[0],
        "dry_run": bool(args.dry_run),
        "backup_path": str(backup_path) if backup_path else None,
        "peers_updated": summary.peers_updated,
        "connections_updated": summary.connections_updated,
        "usage_rows_updated": summary.usage_rows_updated,
        "daily_rows_updated": summary.daily_rows_updated,
    }
    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
