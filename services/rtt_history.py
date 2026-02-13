"""
Rolling RTT history persistence and rollups.

This is used by Barbados/EU recommendation scoring to incorporate recent
infrastructure RTT observations (control plane -> VPN node).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from statistics import mean
from typing import Iterable, Optional

from sqlalchemy.orm import Session

from models.vpn_server_rtt_sample import VPNServerRTTSample


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        return int(raw)
    except ValueError:
        return default


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return float(ordered[f] + (k - f) * (ordered[c] - ordered[f]))


@dataclass(frozen=True)
class RTTRollup:
    sample_count: int
    avg_ms: float
    p95_ms: float
    max_ms: float
    window_seconds: int
    source: str


def record_rtt_sample(
    db: Session,
    *,
    vpn_server_id: int,
    rtt_ms: float,
    source: str = "health_monitor_ping",
) -> None:
    """
    Record a single RTT sample and apply TTL cleanup.

    TTL defaults to 6 hours and can be overridden with:
    - SECUREWAVE_RTT_HISTORY_TTL_SECONDS
    """
    ttl_seconds = max(60, _env_int("SECUREWAVE_RTT_HISTORY_TTL_SECONDS", 6 * 3600))
    cutoff = datetime.utcnow() - timedelta(seconds=ttl_seconds)

    db.add(
        VPNServerRTTSample(
            vpn_server_id=vpn_server_id,
            rtt_ms=float(rtt_ms),
            source=source,
        )
    )

    # Best-effort cleanup to keep the table bounded.
    db.query(VPNServerRTTSample).filter(
        VPNServerRTTSample.vpn_server_id == vpn_server_id,
        VPNServerRTTSample.observed_at < cutoff,
    ).delete(synchronize_session=False)


def get_rtt_rollup(
    db: Session,
    *,
    vpn_server_id: int,
    window_seconds: int = 15 * 60,
    min_samples: int = 5,
) -> Optional[RTTRollup]:
    """
    Compute a rolling RTT rollup from recent samples within window_seconds.

    Returns None if there are fewer than min_samples samples in the window.
    """
    window_seconds = max(30, int(window_seconds))
    cutoff = datetime.utcnow() - timedelta(seconds=window_seconds)
    rows = (
        db.query(VPNServerRTTSample.rtt_ms)
        .filter(
            VPNServerRTTSample.vpn_server_id == vpn_server_id,
            VPNServerRTTSample.observed_at >= cutoff,
        )
        .order_by(VPNServerRTTSample.observed_at.desc())
        .limit(500)
        .all()
    )
    values = [float(item[0]) for item in rows if item and item[0] is not None]
    if len(values) < min_samples:
        return None

    return RTTRollup(
        sample_count=len(values),
        avg_ms=round(mean(values), 3),
        p95_ms=round(_percentile(values, 95), 3),
        max_ms=round(max(values), 3),
        window_seconds=window_seconds,
        source="db_samples",
    )

