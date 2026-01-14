from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from models.vpn_demo_session import VPNDemoSession


DEFAULT_REGION = "us-east"


def _assign_mock_ip(user_id: int) -> str:
    octet = (user_id % 240) + 10
    return f"10.8.0.{octet}"


def get_or_create_session(db: Session, user_id: int) -> VPNDemoSession:
    session = db.query(VPNDemoSession).filter(VPNDemoSession.user_id == user_id).first()
    if session:
        return session
    session = VPNDemoSession(user_id=user_id, status="DISCONNECTED", updated_at=datetime.utcnow())
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


def connect(db: Session, user_id: int, region: Optional[str] = None) -> VPNDemoSession:
    session = get_or_create_session(db, user_id)
    selected_region = region or session.region or DEFAULT_REGION
    session.status = "CONNECTING"
    session.region = selected_region
    session.assigned_node = f"demo-{selected_region}-1"
    session.mock_ip = _assign_mock_ip(user_id)
    session.connected_since = None
    session.last_error = None
    session.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(session)
    return session


def disconnect(db: Session, user_id: int) -> VPNDemoSession:
    session = get_or_create_session(db, user_id)
    session.status = "DISCONNECTING"
    session.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(session)
    return session


def status(db: Session, user_id: int) -> VPNDemoSession:
    session = get_or_create_session(db, user_id)
    now = datetime.utcnow()
    if session.status == "CONNECTING":
        if (now - session.updated_at).total_seconds() >= 1:
            session.status = "CONNECTED"
            session.connected_since = now
            session.updated_at = now
            db.commit()
            db.refresh(session)
    if session.status == "DISCONNECTING":
        if (now - session.updated_at).total_seconds() >= 1:
            session.status = "DISCONNECTED"
            session.connected_since = None
            session.updated_at = now
            db.commit()
            db.refresh(session)
    return session


def build_demo_config(session: VPNDemoSession) -> str:
    region = session.region or DEFAULT_REGION
    assigned_node = session.assigned_node or f"demo-{region}-1"
    mock_ip = session.mock_ip or "10.8.0.10"
    return (
        "[Interface]\n"
        "PrivateKey = DEMO_PRIVATE_KEY\n"
        f"Address = {mock_ip}/32\n"
        "DNS = 1.1.1.1\n\n"
        "[Peer]\n"
        "PublicKey = DEMO_SERVER_PUBLIC_KEY\n"
        f"Endpoint = {assigned_node}.securewave.demo:51820\n"
        "AllowedIPs = 0.0.0.0/0, ::/0\n"
        "PersistentKeepalive = 25\n"
    )
