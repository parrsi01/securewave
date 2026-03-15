"""
SecureWave VPN - Connection Metrics Routes

Client-side metrics ingest and admin query endpoint.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_metric import VPNMetric
from services.jwt_service import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["vpn-metrics"])


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class MetricSubmission(BaseModel):
    server_id: str
    device_id: Optional[int] = None
    handshake_time_ms: Optional[float] = Field(None, ge=0, le=60_000)
    latency_ms: Optional[float] = Field(None, ge=0, le=10_000)
    packet_loss_pct: Optional[float] = Field(None, ge=0, le=100)
    throughput_mbps: Optional[float] = Field(None, ge=0, le=100_000)
    protocol: str = "wireguard"


# ---------------------------------------------------------------------------
# Client ingest
# ---------------------------------------------------------------------------

@router.post("/api/vpn/metrics", status_code=201)
def submit_vpn_metric(
    body: MetricSubmission,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Accept a client-reported connection quality sample."""
    metric = VPNMetric(
        user_id=current_user.id,
        device_id=body.device_id,
        server_id=body.server_id,
        handshake_time_ms=body.handshake_time_ms,
        latency_ms=body.latency_ms,
        packet_loss_pct=body.packet_loss_pct,
        throughput_mbps=body.throughput_mbps,
        protocol=body.protocol,
    )
    db.add(metric)
    db.commit()
    db.refresh(metric)
    return {"status": "ok", "metric_id": metric.id}


# ---------------------------------------------------------------------------
# Admin query
# ---------------------------------------------------------------------------

def _require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin required")
    return current_user


@router.get("/api/admin/vpn-metrics")
def get_vpn_metrics(
    server_id: Optional[str] = Query(None),
    hours: int = Query(24, ge=1, le=720),
    db: Session = Depends(get_db),
    _admin: User = Depends(_require_admin),
):
    """
    Aggregated VPN connection metrics for the admin dashboard.

    Returns per-server averages for handshake time, latency, packet loss,
    and throughput over the requested window.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)

    query = db.query(
        VPNMetric.server_id,
        func.count(VPNMetric.id).label("sample_count"),
        func.avg(VPNMetric.handshake_time_ms).label("avg_handshake_ms"),
        func.avg(VPNMetric.latency_ms).label("avg_latency_ms"),
        func.avg(VPNMetric.packet_loss_pct).label("avg_packet_loss_pct"),
        func.avg(VPNMetric.throughput_mbps).label("avg_throughput_mbps"),
        func.min(VPNMetric.latency_ms).label("min_latency_ms"),
        func.max(VPNMetric.latency_ms).label("max_latency_ms"),
        func.max(VPNMetric.recorded_at).label("latest_sample"),
    ).filter(VPNMetric.recorded_at >= cutoff)

    if server_id:
        query = query.filter(VPNMetric.server_id == server_id)

    rows = query.group_by(VPNMetric.server_id).all()

    servers = []
    for row in rows:
        servers.append({
            "server_id": row.server_id,
            "sample_count": row.sample_count,
            "avg_handshake_ms": round(row.avg_handshake_ms, 2) if row.avg_handshake_ms else None,
            "avg_latency_ms": round(row.avg_latency_ms, 2) if row.avg_latency_ms else None,
            "avg_packet_loss_pct": round(row.avg_packet_loss_pct, 2) if row.avg_packet_loss_pct else None,
            "avg_throughput_mbps": round(row.avg_throughput_mbps, 2) if row.avg_throughput_mbps else None,
            "min_latency_ms": round(row.min_latency_ms, 2) if row.min_latency_ms else None,
            "max_latency_ms": round(row.max_latency_ms, 2) if row.max_latency_ms else None,
            "latest_sample": row.latest_sample.isoformat() if row.latest_sample else None,
        })

    return {
        "window_hours": hours,
        "servers": servers,
    }
