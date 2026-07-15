"""Scoped, encrypted IKEv2 EAP credential records.

IKEv2 uses a distinct, opaque EAP-MSCHAPv2 identity for each SecureWave
device/server assignment.  The backend retains only an encrypted copy of the
short-lived secret needed to re-issue a profile; the server receives it over
its authenticated SSH control channel and stores it root-only.
"""

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, String

from database.base import Base
from utils.time_utils import utcnow


class Ikev2Credential(Base):
    __tablename__ = "ikev2_credentials"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(
        Integer, ForeignKey("wireguard_peers.id"), nullable=False, index=True
    )
    server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=False, index=True)

    # The username is deliberately opaque and non-identifying.  The password
    # is never logged or persisted in plaintext by the backend.
    username = Column(String(96), nullable=False, unique=True, index=True)
    password_encrypted = Column(String, nullable=False)

    issued_at = Column(DateTime, nullable=False, default=utcnow)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    remote_synced_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True, index=True)

    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    __table_args__ = (
        Index(
            "uq_ikev2_credential_active_device_server",
            "user_id",
            "device_id",
            "server_id",
            unique=True,
            sqlite_where=(revoked_at.is_(None)),
            postgresql_where=(revoked_at.is_(None)),
        ),
    )
