from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from backend.services.traffic_manager import get_traffic_manager
from backend.services.traffic_shaper import get_traffic_shaper

router = APIRouter(prefix="/api/vpn", tags=["vpn-metering"])


class StartMeterRequest(BaseModel):
    user_id: int = Field(..., ge=1)
    protocol: str = Field(..., min_length=3)
    session_id: Optional[str] = None
    iface_hint: Optional[str] = None


class StopMeterRequest(BaseModel):
    session_id: str = Field(..., min_length=3)


class StartShapingRequest(BaseModel):
    user_id: int = Field(..., ge=1)
    protocol: str = Field(..., min_length=3)
    tier: str = Field("free", min_length=3)
    session_id: Optional[str] = None
    iface_hint: Optional[str] = None


class StopShapingRequest(BaseModel):
    session_id: str = Field(..., min_length=3)


@router.post("/meter/start")
async def start_meter(request: StartMeterRequest) -> dict:
    manager = get_traffic_manager()
    try:
        return manager.start_meter(
            user_id=request.user_id,
            protocol=request.protocol.lower(),
            session_id=request.session_id,
            iface_hint=request.iface_hint,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/meter/stop")
async def stop_meter(request: StopMeterRequest) -> dict:
    manager = get_traffic_manager()
    stopped = manager.stop_meter(request.session_id)
    if not stopped.get("stopped"):
        raise HTTPException(status_code=404, detail="session not found")
    return stopped


@router.get("/meter/usage/{user_id}")
async def meter_usage(user_id: int, protocol: Optional[str] = Query(default=None)) -> dict:
    manager = get_traffic_manager()
    return {
        "user_id": user_id,
        "current_session_usage": manager.current_session_usage(user_id=user_id, protocol=protocol),
        "last_session_usage": manager.last_session_usage(user_id=user_id),
    }


@router.post("/shaping/start")
async def start_shaping(request: StartShapingRequest) -> dict:
    try:
        return get_traffic_shaper().apply_for_session(
            user_id=request.user_id,
            protocol=request.protocol.lower(),
            tier=request.tier,
            session_id=request.session_id or "",
            iface_hint=request.iface_hint,
        )
    except (FileNotFoundError, RuntimeError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/shaping/stop")
async def stop_shaping(request: StopShapingRequest) -> dict:
    result = get_traffic_shaper().remove_for_session(request.session_id)
    if not result.get("removed"):
        raise HTTPException(status_code=404, detail="session not found")
    return result
