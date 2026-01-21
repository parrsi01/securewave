"""
WireGuard Peer Model - Track individual client configurations and keys
"""

from datetime import datetime
from typing import Dict, Optional
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Boolean, Index
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class WireGuardPeer(Base):
    """
    WireGuard peer (client) configuration
    Tracks keys, IP allocations, and server assignments
    """
    __tablename__ = "wireguard_peers"
    __table_args__ = (
        Index('ix_peer_user_server', 'user_id', 'server_id'),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=True, index=True)  # NULL = default/any server

    # WireGuard keys
    public_key = Column(String, nullable=False, unique=True, index=True)
    private_key_encrypted = Column(String, nullable=False)  # Encrypted private key

    # Network configuration
    ipv4_address = Column(String, nullable=False)  # 10.8.0.x/32
    ipv6_address = Column(String, nullable=True)  # Optional IPv6

    # Peer details
    device_name = Column(String, nullable=True)  # User's device name (optional)
    device_type = Column(String, nullable=True)  # windows, macos, linux, ios, android

    # Status
    is_active = Column(Boolean, default=True)  # Can be deactivated without deletion
    is_revoked = Column(Boolean, default=False)  # Key has been revoked

    # Key rotation
    key_version = Column(Integer, default=1)  # Increments on rotation
    last_key_rotation_at = Column(DateTime, nullable=True)
    next_key_rotation_at = Column(DateTime, nullable=True)  # Scheduled rotation

    # Usage tracking
    last_handshake_at = Column(DateTime, nullable=True)  # Last successful WireGuard handshake
    total_data_sent = Column(Integer, default=0)  # Bytes
    total_data_received = Column(Integer, default=0)  # Bytes
    connection_count = Column(Integer, default=0)  # Number of connection sessions

    # Timestamps
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)
    revoked_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", backref="wireguard_peers")
    server = relationship("VPNServer", backref="wireguard_peers")

    def __repr__(self):
        return f"<WireGuardPeer(user_id={self.user_id}, ip={self.ipv4_address}, active={self.is_active})>"

    @property
    def needs_rotation(self) -> bool:
        """Check if peer needs key rotation"""
        if not self.next_key_rotation_at:
            return False
        return utcnow() >= self.next_key_rotation_at

    @property
    def days_since_rotation(self) -> int:
        """Days since last key rotation"""
        if not self.last_key_rotation_at:
            return (utcnow() - self.created_at).days
        return (utcnow() - self.last_key_rotation_at).days

    @property
    def is_recently_active(self) -> bool:
        """Check if peer was active in last 24 hours"""
        if not self.last_handshake_at:
            return False
        hours_since_handshake = (utcnow() - self.last_handshake_at).total_seconds() / 3600
        return hours_since_handshake < 24

    def to_dict(self, include_private_key: bool = False) -> Dict:
        """Convert to dictionary"""
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "server_id": self.server_id,
            "public_key": self.public_key,
            "ipv4_address": self.ipv4_address,
            "ipv6_address": self.ipv6_address,
            "device_name": self.device_name,
            "device_type": self.device_type,
            "is_active": self.is_active,
            "is_revoked": self.is_revoked,
            "key_version": self.key_version,
            "last_handshake_at": self.last_handshake_at.isoformat() if self.last_handshake_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "needs_rotation": self.needs_rotation,
            "days_since_rotation": self.days_since_rotation,
        }

        if include_private_key:
            data["private_key_encrypted"] = self.private_key_encrypted

        return data
