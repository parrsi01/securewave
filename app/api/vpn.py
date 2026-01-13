from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.devices import get_device_from_header
from app.core import config
from app.models.device import Device
from app.models.user import User
from app.api.auth import get_current_user, require_admin
from app.services import vpn_service
from app.db.session import get_db

router = APIRouter(prefix="/vpn", tags=["vpn"])

class VPNConfigRequest(BaseModel):
    server_id: str | None = None


class VPNServerCreateRequest(BaseModel):
    server_id: str
    location: str
    endpoint: str
    wg_public_key: str
    region: str | None = None
    dns: str | None = None
    allowed_ips: str | None = None
    persistent_keepalive: str | None = None
    status: str | None = "active"


@router.post("/config")
def get_config(
    payload: VPNConfigRequest | None,
    device: Device = Depends(get_device_from_header),
    db: Session = Depends(get_db)
):
    server_id = payload.server_id if payload else None
    server = vpn_service.get_server(db, server_id)
    if not server:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="VPN server not available")
    config_text = vpn_service.build_wireguard_config(device.id, server)
    return {
        "device_id": device.id,
        "config": config_text,
        "endpoint": server.endpoint,
        "dns": server.dns or config.WG_DNS,
        "allowed_ips": server.allowed_ips or config.WG_ALLOWED_IPS,
        "server_id": server.server_id,
        "location": server.location,
    }


@router.get("/servers")
def list_servers(
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    servers = vpn_service.list_servers(db)
    return [
        {
            "server_id": server.server_id,
            "location": server.location,
            "region": server.region,
            "endpoint": server.endpoint,
            "wg_public_key": server.wg_public_key,
            "status": server.status,
            "is_active": server.is_active,
        }
        for server in servers
    ]


@router.post("/servers")
def create_server(
    payload: VPNServerCreateRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    existing = vpn_service.get_server(db, payload.server_id)
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Server already exists")
    server = vpn_service.create_server(
        db=db,
        server_id=payload.server_id,
        location=payload.location,
        endpoint=payload.endpoint,
        wg_public_key=payload.wg_public_key,
        region=payload.region,
        dns=payload.dns,
        allowed_ips=payload.allowed_ips,
        persistent_keepalive=payload.persistent_keepalive,
        status=payload.status or "active",
    )
    return {"server_id": server.server_id, "status": server.status}


@router.post("/servers/{server_id}/deactivate")
def deactivate_server(
    server_id: str,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    server = vpn_service.deactivate_server(db, server_id)
    if not server:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Server not found")
    return {"server_id": server.server_id, "status": "deactivated"}
