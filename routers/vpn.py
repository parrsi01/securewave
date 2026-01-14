from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.demo_vpn_service import connect, disconnect, status as get_status, build_demo_config

router = APIRouter()


class VPNConnectRequest(BaseModel):
    region: Optional[str] = None


class VPNDisconnectRequest(BaseModel):
    reason: Optional[str] = None


@router.post("/connect")
def connect_vpn(
    payload: VPNConnectRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    session = connect(db, current_user.id, payload.region)
    return {
        "mode": "demo",
        "status": session.status,
        "session_id": session.id,
        "connected_since": session.connected_since.isoformat() if session.connected_since else None,
        "region": session.region,
        "assigned_node": session.assigned_node,
        "mock_ip": session.mock_ip,
    }


@router.post("/disconnect")
def disconnect_vpn(
    payload: VPNDisconnectRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    session = disconnect(db, current_user.id)
    return {
        "mode": "demo",
        "status": session.status,
        "disconnected_at": datetime.utcnow().isoformat(),
        "last_error": session.last_error,
    }


@router.get("/status")
def vpn_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    session = get_status(db, current_user.id)
    return {
        "mode": "demo",
        "status": session.status,
        "connected_since": session.connected_since.isoformat() if session.connected_since else None,
        "region": session.region,
        "assigned_node": session.assigned_node,
        "mock_ip": session.mock_ip,
        "last_error": session.last_error,
    }


@router.get("/config")
def vpn_config(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    session = get_status(db, current_user.id)
    if session.status != "CONNECTED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="VPN not connected")
    return {
        "mode": "demo",
        "config": build_demo_config(session),
    }
