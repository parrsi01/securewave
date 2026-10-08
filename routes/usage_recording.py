"""Owner-readable history and narrowly scoped, cumulative recorder submissions."""
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_connection import VPNConnection
from services.jwt_service import get_current_user
from services.usage_metering_service import UsageMeteringError, UsageMeteringService
from services.monthly_usage import monthly_summary

router = APIRouter()


@router.get("/usage/monthly")
async def monthly_usage(current_user: User = Depends(get_current_user),
                        db: Session = Depends(get_db),
                        session_ids: list[int] = Query(default=[], max_length=100)):
    # Reading usage must remain possible after exhausting the allowance.
    return monthly_summary(db, current_user, session_ids)


class UsageCheckpoint(BaseModel):
    model_config = ConfigDict(extra="forbid")
    sequence: int = Field(..., gt=0, le=2**63 - 1, strict=True)
    bytes_sent: int = Field(..., ge=0, le=2**63 - 1, strict=True)
    bytes_received: int = Field(..., ge=0, le=2**63 - 1, strict=True)
    final: bool = Field(False, strict=True)
    verified: bool = Field(False, strict=True)
    gap: bool = Field(False, strict=True)
    reason: Literal["client_disconnect", "app_exit", "app_crash", "system_shutdown",
                    "connect_failed", "counter_reset", "recording_error", "interrupted"] = "client_disconnect"
    stopped_at: Optional[datetime] = None

    @field_validator("stopped_at")
    @classmethod
    def utc_timestamp(cls, value):
        if value is not None and value.tzinfo is not None:
            return value.astimezone(timezone.utc).replace(tzinfo=None)
        return value


def history_payload(connection):
    return {
        "session_id": connection.id,
        "device_id": connection.device_id,
        "server_id": connection.server.server_id if connection.server else None,
        "protocol": connection.protocol,
        "connected_at": connection.connected_at.isoformat(),
        "disconnected_at": connection.disconnected_at.isoformat() if connection.disconnected_at else None,
        "bytes_sent": int(connection.total_bytes_sent or 0),
        "bytes_received": int(connection.total_bytes_received or 0),
        "last_sequence": int(connection.last_meter_sequence or 0),
        "final_sequence": connection.final_meter_sequence,
        "recording_quality": connection.recording_quality,
        "finalization_reason": connection.finalization_reason,
        "metering_version": connection.metering_version,
        "client_verified_at": connection.client_verified_at.isoformat() if connection.client_verified_at else None,
    }


@router.get("/usage/sessions")
async def usage_history(current_user: User = Depends(get_current_user),
                        db: Session = Depends(get_db),
                        limit: int = Query(50, ge=1, le=100),
                        before_id: Optional[int] = Query(None, gt=0)):
    query = db.query(VPNConnection).filter(VPNConnection.user_id == current_user.id)
    if before_id is not None:
        query = query.filter(VPNConnection.id < before_id)
    rows = query.order_by(VPNConnection.id.desc()).limit(limit + 1).all()
    return {"sessions": [history_payload(row) for row in rows[:limit]],
            "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


@router.post("/usage/sessions/{session_id}/checkpoint")
async def usage_checkpoint(session_id: int, payload: UsageCheckpoint,
                           authorization: Optional[str] = Header(None),
                           db: Session = Depends(get_db)):
    import re
    token = authorization.removeprefix("UsageSession ") if authorization else ""
    if not authorization or not authorization.startswith("UsageSession ") or not re.fullmatch("[0-9a-f]{64}", token):
        raise HTTPException(status_code=401, detail="Session reporting authorization required.")
    try:
        result = UsageMeteringService(db).checkpoint(
            connection_id=session_id, reporting_token=token, **payload.model_dump())
    except UsageMeteringError as exc:
        db.rollback()
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    response = history_payload(result.connection)
    response["idempotent"] = result.idempotent
    return response
