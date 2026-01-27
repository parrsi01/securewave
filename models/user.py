from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Integer, String
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=utcnow)
    is_active = Column(Boolean, default=True)
    is_admin = Column(Boolean, default=False)

    # VPN Keys
    wg_public_key = Column(String, nullable=True)
    wg_private_key_encrypted = Column(String, nullable=True)
    wg_peer_registered = Column(Boolean, default=False)  # True when peer is added to WG server

    # Legacy subscription fields (deprecated - use Subscription model instead)
    subscription_status = Column(String, default="basic")
    stripe_customer_id = Column(String, nullable=True)
    paypal_subscription_id = Column(String, nullable=True)

    # Email verification
    email_verified = Column(Boolean, default=False)
    email_verification_token = Column(String, nullable=True, index=True)
    email_verification_token_expires = Column(DateTime, nullable=True)

    # Password reset
    password_reset_token = Column(String, nullable=True, index=True)
    password_reset_token_expires = Column(DateTime, nullable=True)
    password_reset_requested_at = Column(DateTime, nullable=True)

    # Two-Factor Authentication (TOTP)
    totp_secret = Column(String, nullable=True)  # Encrypted TOTP secret
    totp_enabled = Column(Boolean, default=False)
    totp_backup_codes = Column(String, nullable=True)  # Encrypted backup codes (JSON)

    # Security tracking
    last_login = Column(DateTime, nullable=True)
    last_login_ip = Column(String, nullable=True)
    failed_login_attempts = Column(Integer, default=0)
    account_locked_until = Column(DateTime, nullable=True)

    # Relationships
    subscriptions = relationship("Subscription", back_populates="user")

    @property
    def is_locked(self) -> bool:
        """Check if account is locked due to failed login attempts"""
        if not self.account_locked_until:
            return False
        return utcnow() < self.account_locked_until

    @property
    def requires_email_verification(self) -> bool:
        """Check if user needs to verify their email"""
        return not self.email_verified

    @property
    def has_2fa_enabled(self) -> bool:
        """Check if user has 2FA enabled"""
        return self.totp_enabled and self.totp_secret is not None
