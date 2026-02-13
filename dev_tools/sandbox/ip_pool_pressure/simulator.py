from __future__ import annotations

import csv
import json
import os
import random
import secrets
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database.base import Base
from models.user import User
from models.wireguard_peer import WireGuardPeer
from services.vpn_peer_manager import VPNPeerManager


def _utc_now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def _write_csv(path: Path, rows: list[dict[str, Any]], header: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key) for key in header})
    tmp.replace(path)


def _ensure_tables(engine) -> None:
    from models import (  # noqa: F401
        user,
        subscription,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
        wireguard_peer,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        email_log,
        auth_refresh_token,
        jwt_blacklist_token,
    )
    Base.metadata.create_all(bind=engine)


@dataclass(frozen=True)
class IPPoolPressureConfig:
    peers: int = 500
    cycles: int = 10
    churn_per_cycle: int = 50
    seed: int = 1337
    base_cidr: str = "10.250.0.0/22"
    max_blocks: int = 1
    reserved_hosts: int = 510  # capacity ~= 512
    alert_threshold_pct: int = 90


def _set_pool_env(cfg: IPPoolPressureConfig) -> dict[str, str]:
    """
    Return env var overrides for VPNPeerManager allocator logic.
    """
    return {
        "WG_IP_POOL_BASE_CIDR": cfg.base_cidr,
        "WG_IP_POOL_MAX_BLOCKS": str(cfg.max_blocks),
        "WG_IP_POOL_RESERVED_HOSTS": str(cfg.reserved_hosts),
        "WG_IP_EXHAUSTION_ALERT_PCT": str(cfg.alert_threshold_pct),
    }


def _create_user(db, *, idx: int) -> User:
    user = User(
        email=f"ip-pressure-{idx}-{int(time.time())}@example.com",
        hashed_password="x",
        email_verified=True,
        is_active=True,
        created_at=datetime.utcnow(),
        subscription_status="active",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _create_peer_fast(manager: VPNPeerManager, *, user: User) -> WireGuardPeer:
    """
    Create a peer without generating crypto keys (IP allocator pressure harness).
    """
    ip = manager._allocate_ip_address(user.id)  # intentional: simulator uses production allocator logic
    peer = WireGuardPeer(
        user_id=user.id,
        server_id=None,
        public_key=secrets.token_urlsafe(32),
        private_key_encrypted="simulated",
        ipv4_address=ip,
        device_name="ip-pool-pressure",
        device_type="linux",
        is_active=True,
        is_revoked=False,
        key_version=1,
    )
    manager.db.add(peer)
    manager.db.commit()
    manager.db.refresh(peer)
    return peer


def simulate_ip_pool_pressure(
    *,
    cfg: IPPoolPressureConfig,
    output_dir: Optional[Path] = None,
) -> dict[str, Any]:
    prev_env = dict(os.environ)
    os.environ.update(_set_pool_env(cfg))

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    _ensure_tables(engine)

    db = SessionLocal()
    try:
        manager = VPNPeerManager(db)
        rng = random.Random(int(cfg.seed))

        peers_active: dict[int, WireGuardPeer] = {}
        revoked_ips_total: set[str] = set()
        exhaustion_errors = 0

        cycle_rows: list[dict[str, Any]] = []

        # Stage 1: Allocate initial peers.
        for idx in range(1, cfg.peers + 1):
            user = _create_user(db, idx=idx)
            peer = _create_peer_fast(manager, user=user)
            peers_active[peer.id] = peer

        # Stage 2: Churn cycles with reclaim.
        next_user_idx = cfg.peers + 1
        for cycle in range(1, max(1, cfg.cycles) + 1):
            to_revoke = min(cfg.churn_per_cycle, len(peers_active))
            revoke_ids = rng.sample(list(peers_active.keys()), to_revoke) if to_revoke else []
            revoked_ips_cycle: set[str] = set()
            for peer_id in revoke_ids:
                peer = peers_active.pop(peer_id)
                revoked_ips_cycle.add(peer.ipv4_address)
                revoked_ips_total.add(peer.ipv4_address)
                manager.revoke_peer(peer.id)

            # Allocate replacements (should reclaim many of the revoked addresses under pressure).
            new_allocated = 0
            reclaimed = 0
            for _ in range(to_revoke):
                user = _create_user(db, idx=next_user_idx)
                next_user_idx += 1
                try:
                    peer = _create_peer_fast(manager, user=user)
                except ValueError:
                    exhaustion_errors += 1
                    continue
                new_allocated += 1
                if peer.ipv4_address in revoked_ips_total:
                    reclaimed += 1
                peers_active[peer.id] = peer

            # Validate uniqueness among active peers.
            active_ips = [peer.ipv4_address for peer in peers_active.values()]
            unique_active_ips = len(set(active_ips)) == len(active_ips)

            pool_stats = manager.get_ip_pool_stats()
            cycle_rows.append(
                {
                    "cycle": cycle,
                    "active_peers": len(peers_active),
                    "revoked_this_cycle": len(revoke_ids),
                    "allocated_this_cycle": new_allocated,
                    "reclaimed_this_cycle": reclaimed,
                    "unique_active_ips": unique_active_ips,
                    "capacity": pool_stats.get("capacity"),
                    "allocated": pool_stats.get("allocated"),
                    "available": pool_stats.get("available"),
                    "utilization_pct": pool_stats.get("utilization_pct"),
                    "alert_triggered": bool(pool_stats.get("alert")),
                    "exhaustion_errors_total": exhaustion_errors,
                }
            )

        # Stage 3: Force an exhaustion edge-case (bounded) to validate alerting.
        forced_exhaustion_attempts = 0
        for _ in range(64):
            user = _create_user(db, idx=next_user_idx)
            next_user_idx += 1
            try:
                _create_peer_fast(manager, user=user)
            except ValueError:
                exhaustion_errors += 1
                forced_exhaustion_attempts += 1
                break

        final_stats = manager.get_ip_pool_stats()

        report: dict[str, Any] = {
            "harness": "ip_pool_pressure",
            "generated_at": _utc_now_iso(),
            "config": {
                "peers": cfg.peers,
                "cycles": cfg.cycles,
                "churn_per_cycle": cfg.churn_per_cycle,
                "base_cidr": cfg.base_cidr,
                "max_blocks": cfg.max_blocks,
                "reserved_hosts": cfg.reserved_hosts,
                "alert_threshold_pct": cfg.alert_threshold_pct,
            },
            "summary": {
                "active_peers_final": len(peers_active),
                "exhaustion_errors_total": exhaustion_errors,
                "forced_exhaustion_attempts": forced_exhaustion_attempts,
                "final_pool_stats": final_stats,
            },
            "cycles": cycle_rows,
        }

        if output_dir is not None:
            out_dir = Path(output_dir)
            _atomic_write(out_dir / "report.json", json.dumps(report, indent=2, sort_keys=True) + "\n")
            _write_csv(
                out_dir / "summary.csv",
                cycle_rows,
                [
                    "cycle",
                    "active_peers",
                    "revoked_this_cycle",
                    "allocated_this_cycle",
                    "reclaimed_this_cycle",
                    "unique_active_ips",
                    "capacity",
                    "allocated",
                    "available",
                    "utilization_pct",
                    "alert_triggered",
                    "exhaustion_errors_total",
                ],
            )

        return report
    finally:
        db.close()
        os.environ.clear()
        os.environ.update(prev_env)
