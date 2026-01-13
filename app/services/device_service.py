import secrets
from datetime import datetime
from typing import Optional, List

from sqlalchemy.orm import Session

from app.core import config, security
from app.models.device import Device


def _generate_device_token() -> str:
    return secrets.token_urlsafe(config.DEVICE_TOKEN_BYTES)


def create_device(db: Session, user_id: int, name: Optional[str] = None) -> tuple[Device, str]:
    device_token = _generate_device_token()
    token_hash = security.hash_token(device_token)
    prefix = security.token_prefix(device_token)
    device = Device(user_id=user_id, name=name, device_token_hash=token_hash, token_prefix=prefix)
    db.add(device)
    db.commit()
    db.refresh(device)
    return device, device_token


def list_devices(db: Session, user_id: int) -> List[Device]:
    return db.query(Device).filter(Device.user_id == user_id).all()


def get_device_by_token(db: Session, device_token: str) -> Optional[Device]:
    token_hash = security.hash_token(device_token)
    device = db.query(Device).filter(Device.device_token_hash == token_hash, Device.is_active == True).first()
    if device:
        device.last_seen_at = datetime.utcnow()
        db.commit()
    return device


def count_devices(db: Session, user_id: int) -> int:
    return db.query(Device).filter(Device.user_id == user_id, Device.is_active == True).count()


def revoke_device(db: Session, device_id: int, user_id: int) -> Optional[Device]:
    device = db.query(Device).filter(Device.id == device_id, Device.user_id == user_id).first()
    if not device:
        return None
    device.is_active = False
    db.commit()
    return device


def rotate_device_token(db: Session, device_id: int, user_id: int) -> Optional[tuple[Device, str]]:
    device = db.query(Device).filter(Device.id == device_id, Device.user_id == user_id, Device.is_active == True).first()
    if not device:
        return None
    new_token = _generate_device_token()
    device.device_token_hash = security.hash_token(new_token)
    device.token_prefix = security.token_prefix(new_token)
    device.last_seen_at = datetime.utcnow()
    db.commit()
    db.refresh(device)
    return device, new_token
