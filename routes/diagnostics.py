import os
from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.session import get_db
from models.audit_log import AuditLog
from models.vpn_demo_session import VPNDemoSession
from services.jwt_service import get_current_user

router = APIRouter(prefix="/api/diagnostics", tags=["diagnostics"])


# ============================================
# Telemetry Ingestion (Day 5)
# ============================================

class TelemetryPayload(BaseModel):
    """Telemetry data from VPN clients"""
    latency_ms: float
    packet_loss: float = 0.0
    jitter_ms: float = 0.0
    uptime_seconds: int = 0
    bytes_sent: int = 0
    bytes_received: int = 0
    server_id: Optional[str] = None
    connection_quality: Optional[str] = None  # "excellent", "good", "fair", "poor"


class TelemetryBatch(BaseModel):
    """Batch of telemetry records"""
    records: List[TelemetryPayload]


# In-memory telemetry store (production would use TimescaleDB or similar)
_telemetry_store: List[dict] = []


@router.post("/telemetry")
def ingest_telemetry(
    payload: TelemetryPayload,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Ingest telemetry from VPN client.
    Stores latency, packet loss, uptime metrics.
    (Day 5: Telemetry ingestion endpoint)
    """
    record = {
        "user_id": current_user.id,
        "timestamp": datetime.utcnow().isoformat(),
        "latency_ms": payload.latency_ms,
        "packet_loss": payload.packet_loss,
        "jitter_ms": payload.jitter_ms,
        "uptime_seconds": payload.uptime_seconds,
        "bytes_sent": payload.bytes_sent,
        "bytes_received": payload.bytes_received,
        "server_id": payload.server_id,
        "connection_quality": payload.connection_quality,
    }

    # Store in memory (limited to last 10000 records)
    _telemetry_store.append(record)
    if len(_telemetry_store) > 10000:
        _telemetry_store.pop(0)

    # Update optimizer with fresh metrics if server_id provided
    if payload.server_id:
        try:
            from services.vpn_optimizer import get_vpn_optimizer
            optimizer = get_vpn_optimizer()
            optimizer.update_server_metrics(payload.server_id, {
                "latency_ms": payload.latency_ms,
                "packet_loss": payload.packet_loss,
                "jitter_ms": payload.jitter_ms,
            })
        except Exception:
            pass  # Non-critical

    return {"status": "accepted", "record_id": len(_telemetry_store)}


@router.post("/telemetry/batch")
def ingest_telemetry_batch(
    batch: TelemetryBatch,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Ingest multiple telemetry records at once"""
    accepted = 0
    for payload in batch.records:
        record = {
            "user_id": current_user.id,
            "timestamp": datetime.utcnow().isoformat(),
            "latency_ms": payload.latency_ms,
            "packet_loss": payload.packet_loss,
            "jitter_ms": payload.jitter_ms,
            "uptime_seconds": payload.uptime_seconds,
            "bytes_sent": payload.bytes_sent,
            "bytes_received": payload.bytes_received,
            "server_id": payload.server_id,
        }
        _telemetry_store.append(record)
        accepted += 1

    # Trim to last 10000
    while len(_telemetry_store) > 10000:
        _telemetry_store.pop(0)

    return {"status": "accepted", "records_accepted": accepted}


# ============================================
# Debug Session Endpoint (Day 10)
# ============================================

@router.get("/debug/session")
def debug_session(
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Debug endpoint for session observability.
    Shows current user session state, VPN status, optimizer stats.
    (Day 10: /debug/session endpoint)
    """
    # Get VPN demo session if exists
    vpn_session = db.query(VPNDemoSession).filter(
        VPNDemoSession.user_id == current_user.id
    ).first()

    vpn_status = None
    if vpn_session:
        vpn_status = {
            "status": vpn_session.status,
            "region": vpn_session.region,
            "assigned_node": vpn_session.assigned_node,
            "mock_ip": vpn_session.mock_ip,
            "connected_since": vpn_session.connected_since.isoformat() if vpn_session.connected_since else None,
            "last_error": vpn_session.last_error,
        }

    # Get optimizer stats
    optimizer_stats = None
    try:
        from services.vpn_optimizer import get_vpn_optimizer
        optimizer = get_vpn_optimizer()
        optimizer_stats = optimizer.get_stats()
    except Exception as e:
        optimizer_stats = {"error": str(e)}

    # Get recent telemetry for this user
    user_telemetry = [
        r for r in _telemetry_store[-100:]
        if r.get("user_id") == current_user.id
    ][-10:]  # Last 10 records

    return {
        "user": {
            "id": current_user.id,
            "email": current_user.email,
            "is_active": current_user.is_active,
            "subscription_status": current_user.subscription_status,
            "has_wg_keys": bool(current_user.wg_public_key),
        },
        "vpn_session": vpn_status,
        "optimizer": optimizer_stats,
        "recent_telemetry": user_telemetry,
        "telemetry_store_size": len(_telemetry_store),
        "timestamp": datetime.utcnow().isoformat(),
    }


@router.get("/summary")
def diagnostics_summary(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    env = os.getenv("ENVIRONMENT", "development")
    demo_mode = os.getenv("DEMO_MODE", "true").lower() == "true"
    db_url = os.getenv("DATABASE_URL", "")
    db_type = "sqlite" if db_url.startswith("sqlite") else "postgres"

    return {
        "environment": env,
        "demo_mode": demo_mode,
        "database": db_type,
        "user_id": current_user.id,
    }


@router.get("/events")
def diagnostics_events(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    events = (
        db.query(AuditLog)
        .order_by(AuditLog.created_at.desc())
        .limit(20)
        .all()
    )
    return [event.to_dict() for event in events]
