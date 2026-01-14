"""
SecureWave VPN - Enhanced Authentication API Routes
Complete authentication system with email verification, password reset, and 2FA
"""

import logging
import os
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from io import BytesIO

from database.session import get_db
from models.user import User
from services.hashing_service import hash_password, verify_password
from services.jwt_service import create_access_token, create_refresh_token, verify_refresh_token, get_current_user
from services.auth_service import AuthService
from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auth", tags=["Authentication"])
DEMO_MODE = os.getenv("DEMO_MODE", "true").lower() == "true"

# Rate limiter
limiter = Limiter(key_func=get_remote_address)


# ===========================
# REQUEST/RESPONSE MODELS
# ===========================

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    totp_code: Optional[str] = None  # For 2FA


class RefreshRequest(BaseModel):
    refresh_token: str


class VerifyEmailRequest(BaseModel):
    token: str


class PasswordResetRequestModel(BaseModel):
    email: EmailStr


class PasswordResetConfirmModel(BaseModel):
    token: str
    new_password: str


class Setup2FAResponse(BaseModel):
    secret: str
    provisioning_uri: str
    backup_codes: list
    qr_code_url: str


class Verify2FARequest(BaseModel):
    totp_code: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    requires_2fa: bool = False


# ===========================
# REGISTRATION & LOGIN
# ===========================

@router.post("/register", response_model=dict, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/hour")  # Prevent abuse
async def register(
    request: Request,
    payload: RegisterRequest,
    db: Session = Depends(get_db)
):
    """
    Register new user with email verification
    """
    try:
        # Check if email already exists
        existing = db.query(User).filter(User.email == payload.email).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )

        # Validate password strength
        if len(payload.password) < 8:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be at least 8 characters long"
            )

        # Create user
        user = User(
            email=payload.email,
            hashed_password=hash_password(payload.password),
            created_at=datetime.utcnow(),
            subscription_status="inactive",
            email_verified=DEMO_MODE,  # Demo: mark verified immediately
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        # Send verification email (demo skips)
        email_sent = False
        if not DEMO_MODE:
            auth_service = AuthService(db)
            email_sent = auth_service.send_verification_email(user)

            if not email_sent:
                logger.warning(f"Failed to send verification email to {user.email}")

        logger.info(f"✓ New user registered: {user.email}")

        if DEMO_MODE:
            return {
                "message": "Registration successful (demo mode).",
                "access_token": create_access_token(user),
                "refresh_token": create_refresh_token(user),
                "token_type": "bearer",
            }

        return {
            "message": "Registration successful. Please check your email to verify your account.",
            "email": user.email,
            "email_sent": email_sent,
            "user_id": user.id
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Registration error: {e}")
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Registration failed"
        )


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")  # Prevent brute force
async def login(
    request: Request,
    payload: LoginRequest,
    db: Session = Depends(get_db)
):
    """
    Login with email and password (and optional 2FA code)
    """
    try:
        # Get user
        user: Optional[User] = db.query(User).filter(User.email == payload.email).first()

        if not user or not verify_password(payload.password, user.hashed_password):
            # Record failed attempt
            if user:
                auth_service = AuthService(db)
                ip_address = request.client.host if request.client else None
                auth_service.record_login_attempt(user, success=False, ip_address=ip_address)

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials"
            )

        # Check if account is locked
        auth_service = AuthService(db)
        if auth_service.is_account_locked(user):
            raise HTTPException(
                status_code=status.HTTP_423_LOCKED,
                detail=f"Account locked due to too many failed login attempts. Try again later."
            )

        # Check if email is verified (optional - can be enforced)
        # if not user.email_verified:
        #     raise HTTPException(
        #         status_code=status.HTTP_403_FORBIDDEN,
        #         detail="Please verify your email before logging in"
        #     )

        # Check 2FA
        if user.has_2fa_enabled:
            if not payload.totp_code:
                # Return response indicating 2FA is required
                return TokenResponse(
                    access_token="",
                    refresh_token="",
                    requires_2fa=True
                )

            # Verify TOTP code
            valid = auth_service.verify_totp(user, payload.totp_code)

            # If TOTP fails, try backup code
            if not valid:
                valid = auth_service.verify_backup_code(user, payload.totp_code)

            if not valid:
                # Record failed attempt
                ip_address = request.client.host if request.client else None
                auth_service.record_login_attempt(user, success=False, ip_address=ip_address)
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid 2FA code"
                )

        # Record successful login
        ip_address = request.client.host if request.client else None
        auth_service.record_login_attempt(user, success=True, ip_address=ip_address)

        logger.info(f"✓ User logged in: {user.email}")

        return TokenResponse(
            access_token=create_access_token(user),
            refresh_token=create_refresh_token(user),
            requires_2fa=False
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Login error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    """Refresh access token"""
    try:
        token_data = verify_refresh_token(payload.refresh_token)
        user = db.query(User).filter(User.id == int(token_data.get("sub"))).first()

        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token"
            )

        return TokenResponse(
            access_token=create_access_token(user),
            refresh_token=create_refresh_token(user),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Token refresh error: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )


@router.post("/logout")
async def logout():
    return {"status": "ok"}


@router.get("/me")
async def get_current_user_info(current_user: User = Depends(get_current_user)):
    """Get current user information"""
    return {
        "id": current_user.id,
        "email": current_user.email,
        "created_at": current_user.created_at.isoformat() if current_user.created_at else None,
        "email_verified": current_user.email_verified,
        "has_2fa": current_user.has_2fa_enabled,
        "subscription_active": current_user.subscription_status == "active",
        "subscription_status": current_user.subscription_status,
        "last_login": current_user.last_login.isoformat() if current_user.last_login else None,
    }


# ===========================
# EMAIL VERIFICATION
# ===========================

@router.post("/verify-email")
async def verify_email(payload: VerifyEmailRequest, db: Session = Depends(get_db)):
    """Verify email address with token"""
    try:
        auth_service = AuthService(db)
        success, error = auth_service.verify_email(payload.token)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error or "Verification failed"
            )

        return {
            "message": "Email verified successfully",
            "verified": True
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Email verification error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Verification failed"
        )


@router.post("/resend-verification")
@limiter.limit("3/hour")
async def resend_verification_email(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Resend verification email"""
    try:
        if current_user.email_verified:
            return {"message": "Email already verified"}

        auth_service = AuthService(db)
        email_sent = auth_service.send_verification_email(current_user)

        if not email_sent:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to send verification email"
            )

        return {"message": "Verification email sent"}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Resend verification error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to resend verification email"
        )


# ===========================
# PASSWORD RESET
# ===========================

@router.post("/password-reset/request")
@limiter.limit("3/hour")  # Prevent abuse
async def request_password_reset(
    request: Request,
    payload: PasswordResetRequestModel,
    db: Session = Depends(get_db)
):
    """Request password reset email"""
    try:
        auth_service = AuthService(db)
        # Always returns success to prevent email enumeration
        auth_service.request_password_reset(payload.email)

        return {
            "message": "If the email exists, a password reset link has been sent"
        }

    except Exception as e:
        logger.error(f"✗ Password reset request error: {e}")
        # Don't reveal errors to prevent enumeration
        return {
            "message": "If the email exists, a password reset link has been sent"
        }


@router.post("/password-reset/confirm")
@limiter.limit("5/hour")
async def confirm_password_reset(
    request: Request,
    payload: PasswordResetConfirmModel,
    db: Session = Depends(get_db)
):
    """Reset password with token"""
    try:
        auth_service = AuthService(db)
        success, error = auth_service.reset_password(
            payload.token,
            payload.new_password
        )

        if not success:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error or "Password reset failed"
            )

        return {
            "message": "Password reset successfully",
            "success": True
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Password reset confirm error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Password reset failed"
        )


# ===========================
# TWO-FACTOR AUTHENTICATION
# ===========================

@router.post("/2fa/setup", response_model=Setup2FAResponse)
async def setup_2fa(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Set up 2FA for user (returns QR code and backup codes)"""
    try:
        if current_user.has_2fa_enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="2FA already enabled"
            )

        auth_service = AuthService(db)
        secret, provisioning_uri, backup_codes = auth_service.setup_2fa(current_user)

        return Setup2FAResponse(
            secret=secret,
            provisioning_uri=provisioning_uri,
            backup_codes=backup_codes,
            qr_code_url=f"/api/auth/2fa/qr?user_id={current_user.id}"
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ 2FA setup error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="2FA setup failed"
        )


@router.get("/2fa/qr")
async def get_2fa_qr_code(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get QR code image for 2FA setup"""
    try:
        if not current_user.totp_secret:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="2FA not set up. Call /2fa/setup first"
            )

        auth_service = AuthService(db)

        # Generate provisioning URI
        import pyotp
        totp = pyotp.TOTP(current_user.totp_secret)
        provisioning_uri = totp.provisioning_uri(
            name=current_user.email,
            issuer_name="SecureWave VPN"
        )

        # Generate QR code
        qr_image_bytes = auth_service.generate_qr_code(provisioning_uri)

        return StreamingResponse(
            BytesIO(qr_image_bytes),
            media_type="image/png"
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ QR code generation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="QR code generation failed"
        )


@router.post("/2fa/verify")
async def verify_and_enable_2fa(
    payload: Verify2FARequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Verify TOTP code and enable 2FA"""
    try:
        auth_service = AuthService(db)
        success, error = auth_service.verify_and_enable_2fa(
            current_user,
            payload.totp_code
        )

        if not success:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error or "Verification failed"
            )

        return {
            "message": "2FA enabled successfully",
            "enabled": True
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ 2FA verification error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="2FA verification failed"
        )


@router.post("/2fa/disable")
async def disable_2fa(
    payload: Verify2FARequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Disable 2FA (requires verification code)"""
    try:
        if not current_user.has_2fa_enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="2FA not enabled"
            )

        auth_service = AuthService(db)

        # Verify code before disabling
        valid = auth_service.verify_totp(current_user, payload.totp_code)
        if not valid:
            valid = auth_service.verify_backup_code(current_user, payload.totp_code)

        if not valid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid verification code"
            )

        # Disable 2FA
        success = auth_service.disable_2fa(current_user)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to disable 2FA"
            )

        return {
            "message": "2FA disabled successfully",
            "enabled": False
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ 2FA disable error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to disable 2FA"
        )


@router.get("/2fa/status")
async def get_2fa_status(current_user: User = Depends(get_current_user)):
    """Get 2FA status for current user"""
    return {
        "enabled": current_user.has_2fa_enabled,
        "email": current_user.email
    }
