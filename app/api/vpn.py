from fastapi import APIRouter, Depends

from app.api.devices import get_device_from_header
from app.core import config
from app.models.device import Device
from app.services import vpn_service

router = APIRouter(prefix="/vpn", tags=["vpn"])


@router.post("/config")
def get_config(device: Device = Depends(get_device_from_header)):
    config_text = vpn_service.build_wireguard_config(device.id)
    return {
        "device_id": device.id,
        "config": config_text,
        "endpoint": config.WG_ENDPOINT,
        "dns": config.WG_DNS,
        "allowed_ips": config.WG_ALLOWED_IPS,
    }
