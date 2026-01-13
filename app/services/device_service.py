import secrets
from datetime import datetime
from typing import Optional, List

from sqlalchemy.orm import Session

from app.core import config
from app.models.device import Device


def create_device(db: Session, user_id: int, name: Optional[str] = None) -> Device:
    device_token = secrets.token_urlsafe(config.DEVICE_TOKEN_BYTES)
    device = Device(user_id=user_id, name=name, device_token=device_token)
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


def list_devices(db: Session, user_id: int) -> List[Device]:
    return db.query(Device).filter(Device.user_id == user_id).all()


def get_device_by_token(db: Session, device_token: str) -> Optional[Device]:
    device = db.query(Device).filter(Device.device_token == device_token).first()
    if device:
        device.last_seen_at = datetime.utcnow()
        db.commit()
    return device
