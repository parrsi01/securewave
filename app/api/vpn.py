from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.devices import get_device_from_header
from app.core import config
from app.models.device import Device
from app.services import vpn_service
from app.db.session import get_db

router = APIRouter(prefix="/vpn", tags=["vpn"])

class VPNConfigRequest(BaseModel):
    server_id: str | None = None


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
