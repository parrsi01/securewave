from fastapi import APIRouter, Depends, HTTPException, Header, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.auth import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.services import device_service
from app.core import config
from app.models.subscription import Subscription

router = APIRouter(prefix="/devices", tags=["devices"])


class DeviceRegisterRequest(BaseModel):
    name: str | None = None


class DeviceRegisterResponse(BaseModel):
    device_id: int
    device_token: str


@router.post("/register", response_model=DeviceRegisterResponse)
def register_device(
    payload: DeviceRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    active_count = device_service.count_devices(db, current_user.id)
    subscription = db.query(Subscription).filter(Subscription.user_id == current_user.id).first()
    if subscription and subscription.status == "active":
        device_limit = subscription.device_limit or config.MAX_DEVICES_PER_USER
    else:
        device_limit = config.FREE_DEVICE_LIMIT
    if active_count >= device_limit:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device limit reached")
    device, token = device_service.create_device(db, current_user.id, payload.name)
    return DeviceRegisterResponse(device_id=device.id, device_token=token)


@router.get("")
def list_devices(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    devices = device_service.list_devices(db, current_user.id)
    return [
        {
            "id": device.id,
            "name": device.name,
            "created_at": device.created_at.isoformat() if device.created_at else None,
            "last_seen_at": device.last_seen_at.isoformat() if device.last_seen_at else None,
            "is_active": device.is_active,
            "token_prefix": device.token_prefix,
        }
        for device in devices
    ]


@router.post("/{device_id}/revoke")
def revoke_device(device_id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = device_service.revoke_device(db, device_id, current_user.id)
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    return {"status": "revoked", "device_id": device.id}


@router.post("/{device_id}/rotate")
def rotate_device(device_id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    result = device_service.rotate_device_token(db, device_id, current_user.id)
    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    device, token = result
    return {"device_id": device.id, "device_token": token}


def get_device_from_header(
    x_device_token: str = Header(..., alias="X-Device-Token"),
    db: Session = Depends(get_db)
):
    device = device_service.get_device_by_token(db, x_device_token)
    if not device:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid device token")
    return device
