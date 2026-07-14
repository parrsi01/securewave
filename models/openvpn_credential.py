"""Scoped, encrypted OpenVPN client credential records.

OpenVPN uses a per-device username/password rather than reusing a WireGuard
key.  The password is encrypted at rest for the short period during which a
profile may be re-issued; the server receives only a salted verifier.
"""

from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, String

from database.base import Base
from utils.time_utils import utcnow


class OpenVpnCredential(Base):
    __tablename__ = "openvpn_credentials"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(
        Integer, ForeignKey("wireguard_peers.id"), nullable=False, index=True
    )
    server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=False, index=True)

    # `username` is opaque and non-identifying. Never store or log the clear
    # password; server-side verification is based on the salt + hash fields.
    username = Column(String(96), nullable=False, unique=True, index=True)
    password_encrypted = Column(String, nullable=False)
    password_salt = Column(String(64), nullable=False)
    password_hash = Column(String(64), nullable=False)

    issued_at = Column(DateTime, nullable=False, default=utcnow)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    remote_synced_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True, index=True)

    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    __table_args__ = (
        Index(
            "uq_openvpn_credential_active_device_server",
            "user_id",
            "device_id",
            "server_id",
            unique=True,
            sqlite_where=(revoked_at.is_(None)),
            postgresql_where=(revoked_at.is_(None)),
        ),
    )
