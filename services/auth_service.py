"""
SecureWave VPN - Authentication Service
Handles email verification, password reset, 2FA, and account security
"""

import secrets
import logging
import json
import base64
from datetime import datetime, timedelta
from typing import Optional, Tuple, List
from sqlalchemy.orm import Session
from cryptography.hazmat.primitives.twofactor.totp import TOTP
from cryptography.hazmat.primitives.hashes import SHA1
from cryptography.hazmat.backends import default_backend
from cryptography.fernet import Fernet, InvalidToken
import pyotp
import qrcode
from io import BytesIO

from config.settings import get_settings
from models.user import User
from models.used_totp_code import UsedTotpCode
from services.email_service import EmailService
from services.hashing_service import hash_password
from utils.password_policy import validate_password_strength
from utils.env_validation import is_testing

logger = logging.getLogger(__name__)
SETTINGS = get_settings()

# Security configuration
EMAIL_VERIFICATION_TOKEN_EXPIRY_HOURS = 24
PASSWORD_RESET_TOKEN_EXPIRY_MINUTES = 15
MAX_FAILED_LOGIN_ATTEMPTS = 5
ACCOUNT_LOCK_DURATION_MINUTES = 30
BACKUP_CODES_COUNT = 10


class AuthService:
    """
    Production-grade authentication service
    Handles email verification, password reset, 2FA, and security features
    """

    def __init__(self, db: Session):
        """Initialize authentication service"""
        self.db = db
        self.email_service = EmailService()
        self.fernet = self._load_fernet()

    # ===========================
    # EMAIL VERIFICATION
    # ===========================

    def generate_verification_token(self) -> str:
        """Generate secure verification token"""
        return secrets.token_urlsafe(32)

    def send_verification_email(self, user: User) -> bool:
        """
        Send email verification link to user

        Args:
            user: User object

        Returns:
            True if email sent successfully
        """
        try:
            # Generate verification token
            token = self.generate_verification_token()
            expires_at = datetime.utcnow() + timedelta(hours=EMAIL_VERIFICATION_TOKEN_EXPIRY_HOURS)

            # Update user
            user.email_verification_token = token
            user.email_verification_token_expires = expires_at
            self.db.commit()

            # Send email
            success = self.email_service.send_verification_email(
                to_email=user.email,
                verification_token=token
            )

            if success:
                logger.info(f"✓ Verification email sent to {user.email}")
            else:
                logger.warning(f"✗ Failed to send verification email to {user.email}")

            return success

        except Exception as e:
            logger.error(f"✗ Error sending verification email: {e}")
            self.db.rollback()
            return False

    def verify_email(self, token: str) -> Tuple[bool, Optional[str]]:
        """
        Verify email with token

        Args:
            token: Verification token from email

        Returns:
            Tuple of (success, error_message)
        """
        try:
            user = self.db.query(User).filter(
                User.email_verification_token == token
            ).first()

            if not user:
                return False, "Invalid verification token"

            # Check if token expired
            if datetime.utcnow() > user.email_verification_token_expires:
                return False, "Verification token has expired"

            # Verify email
            user.email_verified = True
            user.email_verification_token = None
            user.email_verification_token_expires = None
            self.db.commit()

            logger.info(f"✓ Email verified for user: {user.email}")
            return True, None

        except Exception as e:
            logger.error(f"✗ Error verifying email: {e}")
            self.db.rollback()
            return False, "Internal error during verification"

    # ===========================
    # PASSWORD RESET
    # ===========================

    def request_password_reset(self, email: str) -> bool:
        """
        Send password reset email

        Args:
            email: User's email address

        Returns:
            Always returns True for security (don't reveal if email exists)
        """
        try:
            user = self.db.query(User).filter(User.email == email).first()

            if not user:
                # Don't reveal that email doesn't exist
                logger.info(f"Password reset requested for non-existent email: {email}")
                return True

            # Check rate limiting (prevent abuse)
            if user.password_reset_requested_at:
                time_since_last_request = datetime.utcnow() - user.password_reset_requested_at
                if time_since_last_request < timedelta(minutes=5):
                    logger.warning(f"Rate limit: Password reset requested too frequently for {email}")
                    return True  # Don't reveal rate limiting

            # Generate reset token
            token = self.generate_verification_token()
            expires_at = datetime.utcnow() + timedelta(minutes=PASSWORD_RESET_TOKEN_EXPIRY_MINUTES)

            # Update user
            user.password_reset_token = token
            user.password_reset_token_expires = expires_at
            user.password_reset_requested_at = datetime.utcnow()
            self.db.commit()

            # Send email
            success = self.email_service.send_password_reset_email(
                to_email=user.email,
                reset_token=token
            )

            if success:
                logger.info(f"✓ Password reset email sent to {email}")
            else:
                logger.warning(f"✗ Failed to send password reset email to {email}")

            return True

        except Exception as e:
            logger.error(f"✗ Error requesting password reset: {e}")
            self.db.rollback()
            return True  # Don't reveal errors

    def reset_password(self, token: str, new_password: str) -> Tuple[bool, Optional[str]]:
        """
        Reset password with token

        Args:
            token: Reset token from email
            new_password: New password

        Returns:
            Tuple of (success, error_message)
        """
        try:
            user = self.db.query(User).filter(
                User.password_reset_token == token
            ).first()

            if not user:
                return False, "Invalid reset token"

            # Check if token expired
            if datetime.utcnow() > user.password_reset_token_expires:
                return False, "Reset token has expired"

            # Validate password strength
            password_error = validate_password_strength(new_password)
            if password_error:
                return False, password_error

            # Update password
            user.hashed_password = hash_password(new_password)
            user.password_reset_token = None
            user.password_reset_token_expires = None
            user.password_reset_requested_at = None
            user.failed_login_attempts = 0  # Reset failed attempts
            user.account_locked_until = None  # Unlock account
            self.db.commit()

            logger.info(f"✓ Password reset successfully for user: {user.email}")
            return True, None

        except Exception as e:
            logger.error(f"✗ Error resetting password: {e}")
            self.db.rollback()
            return False, "Internal error during password reset"

    # ===========================
    # TWO-FACTOR AUTHENTICATION
    # ===========================
    def _load_fernet(self) -> Optional[Fernet]:
        """
        Load Fernet encryption key for 2FA secret storage.

        SECURITY: This method validates that the encryption key is a valid
        Fernet key (44-byte base64-encoded). Invalid keys cause explicit failure
        rather than silent degradation to prevent weak encryption.
        """
        key = SETTINGS.auth_encryption_key or SETTINGS.wg_encryption_key
        environment = SETTINGS.environment
        if not key:
            if environment == "production":
                logger.error("AUTH_ENCRYPTION_KEY is required in production")
                raise RuntimeError("AUTH_ENCRYPTION_KEY is required in production")
            logger.warning("Auth encryption key not set - 2FA secrets stored with base64 fallback")
            return None
        key_bytes = key.encode()
        # Fernet keys must be exactly 44 bytes (32 bytes base64-encoded)
        if len(key_bytes) != 44:
            error_msg = (
                f"Invalid encryption key length: {len(key_bytes)} bytes (expected 44). "
                "Generate a valid key with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
            )
            logger.error(error_msg)
            raise ValueError(error_msg)
        return Fernet(key_bytes)

    def _encrypt_value(self, value: str) -> str:
        if self.fernet:
            return self.fernet.encrypt(value.encode()).decode()
        # M-AUTH-2: Never fall back to base64 (no encryption) in production.
        # base64 is NOT encryption and must only be used in test environments.
        if is_testing():
            return base64.b64encode(value.encode()).decode()
        raise RuntimeError(
            "Encryption key not configured. TOTP secrets cannot be stored without encryption. "
            "Set AUTH_ENCRYPTION_KEY to a valid Fernet key."
        )

    def _decrypt_value(self, value: str) -> str:
        if not value:
            return ""
        if self.fernet:
            try:
                return self.fernet.decrypt(value.encode()).decode()
            except InvalidToken:
                pass
        try:
            return base64.b64decode(value.encode()).decode()
        except Exception:
            return value

    def generate_totp_secret(self) -> str:
        """Generate TOTP secret for 2FA"""
        return pyotp.random_base32()

    def generate_backup_codes(self, count: int = BACKUP_CODES_COUNT) -> List[str]:
        """
        Generate backup codes for 2FA recovery

        Args:
            count: Number of backup codes to generate

        Returns:
            List of backup codes
        """
        codes = []
        for _ in range(count):
            # L-5: 10 random bytes = 80 bits of entropy (NIST SP 800-63B requires ≥20 bits).
            # Formatted as XXXX-XXXX-XXXX-XXXX-XX for readability (20 hex chars + 4 dashes).
            raw = secrets.token_hex(10).upper()  # 20 hex chars = 80 bits
            code = f"{raw[0:4]}-{raw[4:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}"
            codes.append(code)
        return codes

    def setup_2fa(self, user: User) -> Tuple[str, str, List[str]]:
        """
        Set up 2FA for user (but don't enable yet)

        Args:
            user: User object

        Returns:
            Tuple of (secret, provisioning_uri, backup_codes)
        """
        try:
            # Generate TOTP secret
            secret = self.generate_totp_secret()

            # Generate provisioning URI for QR code
            totp = pyotp.TOTP(secret)
            provisioning_uri = totp.provisioning_uri(
                name=user.email,
                issuer_name="SecureWave VPN"
            )

            # Generate backup codes
            backup_codes = self.generate_backup_codes()

            # Store secret and backup codes (not enabled yet)
            user.totp_secret = self._encrypt_value(secret)
            user.totp_backup_codes = self._encrypt_value(json.dumps(backup_codes))
            user.totp_enabled = False  # Don't enable until verified
            self.db.commit()

            logger.info(f"✓ 2FA setup initiated for user: {user.email}")
            return secret, provisioning_uri, backup_codes

        except Exception as e:
            logger.error(f"✗ Error setting up 2FA: {e}")
            self.db.rollback()
            raise

    def generate_qr_code(self, provisioning_uri: str) -> bytes:
        """
        Generate QR code image for TOTP setup

        Args:
            provisioning_uri: TOTP provisioning URI

        Returns:
            PNG image bytes
        """
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(provisioning_uri)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        return buffer.getvalue()

    def verify_and_enable_2fa(self, user: User, totp_code: str) -> Tuple[bool, Optional[str]]:
        """
        Verify TOTP code and enable 2FA

        Args:
            user: User object
            totp_code: TOTP code from authenticator app

        Returns:
            Tuple of (success, error_message)
        """
        try:
            if not user.totp_secret:
                return False, "2FA not set up"

            # Verify TOTP code
            decrypted_secret = self._decrypt_value(user.totp_secret)
            if not decrypted_secret:
                return False, "2FA not set up"
            totp = pyotp.TOTP(decrypted_secret)
            if not totp.verify(totp_code, valid_window=1):
                return False, "Invalid verification code"

            # L-3: Reject replayed codes even during 2FA setup verification
            if self._is_totp_code_used(user.id, totp_code):
                logger.warning("TOTP replay attempt during 2FA setup for user %s", user.id)
                return False, "TOTP code already used"
            self._record_totp_code_used(user.id, totp_code)

            # Enable 2FA
            user.totp_enabled = True
            self.db.commit()

            # Send confirmation email
            self.email_service.send_2fa_enabled_email(user.email)

            logger.info(f"✓ 2FA enabled for user: {user.email}")
            return True, None

        except Exception as e:
            logger.error(f"✗ Error enabling 2FA: {e}")
            self.db.rollback()
            return False, "Internal error"

    def _is_totp_code_used(self, user_id: int, totp_code: str) -> bool:
        """Return True if this TOTP code was already used within the last 90 seconds."""
        cutoff = datetime.utcnow() - timedelta(seconds=90)
        return (
            self.db.query(UsedTotpCode)
            .filter(
                UsedTotpCode.user_id == user_id,
                UsedTotpCode.code == totp_code,
                UsedTotpCode.used_at > cutoff,
            )
            .first()
            is not None
        )

    def _record_totp_code_used(self, user_id: int, totp_code: str) -> None:
        """Persist a used TOTP code to prevent replay within the 90s window."""
        self.db.add(UsedTotpCode(user_id=user_id, code=totp_code, used_at=datetime.utcnow()))
        # Opportunistic cleanup: delete codes older than 90s for this user to bound table growth.
        cutoff = datetime.utcnow() - timedelta(seconds=90)
        self.db.query(UsedTotpCode).filter(
            UsedTotpCode.user_id == user_id,
            UsedTotpCode.used_at <= cutoff,
        ).delete(synchronize_session=False)
        self.db.commit()

    def verify_totp(self, user: User, totp_code: str) -> bool:
        """
        Verify TOTP code during login.

        L-3: Checks that the code has not already been used within the current
        90-second validity window to prevent replay attacks.

        Args:
            user: User object
            totp_code: TOTP code from authenticator app

        Returns:
            True if valid and not replayed
        """
        if not user.totp_enabled or not user.totp_secret:
            return False

        decrypted_secret = self._decrypt_value(user.totp_secret)
        if not decrypted_secret:
            return False
        totp = pyotp.TOTP(decrypted_secret)
        if not totp.verify(totp_code, valid_window=1):
            return False

        # L-3: Reject replayed codes
        if self._is_totp_code_used(user.id, totp_code):
            logger.warning("TOTP replay attempt blocked for user %s", user.id)
            return False

        self._record_totp_code_used(user.id, totp_code)
        return True

    def verify_backup_code(self, user: User, backup_code: str) -> bool:
        """
        Verify and consume backup code

        Args:
            user: User object
            backup_code: Backup code

        Returns:
            True if valid
        """
        try:
            if not user.totp_backup_codes:
                return False

            decrypted_codes = self._decrypt_value(user.totp_backup_codes)
            backup_codes = json.loads(decrypted_codes)

            if backup_code.upper() in backup_codes:
                # Remove used code
                backup_codes.remove(backup_code.upper())
                user.totp_backup_codes = self._encrypt_value(json.dumps(backup_codes))
                self.db.commit()

                logger.info(f"✓ Backup code used for user: {user.email}")
                return True

            return False

        except Exception as e:
            logger.error(f"✗ Error verifying backup code: {e}")
            return False

    def disable_2fa(self, user: User) -> bool:
        """
        Disable 2FA for user

        Args:
            user: User object

        Returns:
            True if successful
        """
        try:
            user.totp_enabled = False
            user.totp_secret = None
            user.totp_backup_codes = None
            self.db.commit()

            logger.info(f"✓ 2FA disabled for user: {user.email}")
            return True

        except Exception as e:
            logger.error(f"✗ Error disabling 2FA: {e}")
            self.db.rollback()
            return False

    # ===========================
    # ACCOUNT SECURITY
    # ===========================

    def record_login_attempt(
        self,
        user: User,
        success: bool,
        ip_address: Optional[str] = None
    ) -> None:
        """
        Record login attempt and handle account locking

        Args:
            user: User object
            success: Whether login was successful
            ip_address: User's IP address
        """
        try:
            if success:
                # Reset failed attempts on successful login
                user.failed_login_attempts = 0
                user.account_locked_until = None
                user.last_login = datetime.utcnow()
                user.last_login_ip = ip_address
            else:
                # Increment failed attempts
                user.failed_login_attempts += 1

                # Lock account if too many failed attempts
                if user.failed_login_attempts >= MAX_FAILED_LOGIN_ATTEMPTS:
                    user.account_locked_until = datetime.utcnow() + timedelta(
                        minutes=ACCOUNT_LOCK_DURATION_MINUTES
                    )
                    logger.warning(
                        f"⚠️ Account locked due to failed login attempts: {user.email}"
                    )

            self.db.commit()

        except Exception as e:
            logger.error(f"✗ Error recording login attempt: {e}")
            self.db.rollback()

    def is_account_locked(self, user: User) -> bool:
        """Check if account is locked"""
        return user.is_locked

    def unlock_account(self, user: User) -> bool:
        """
        Manually unlock account (admin function)

        Args:
            user: User object

        Returns:
            True if successful
        """
        try:
            user.failed_login_attempts = 0
            user.account_locked_until = None
            self.db.commit()

            logger.info(f"✓ Account unlocked: {user.email}")
            return True

        except Exception as e:
            logger.error(f"✗ Error unlocking account: {e}")
            self.db.rollback()
            return False
