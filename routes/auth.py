"""
SecureWave VPN - Enhanced Authentication API Routes
Complete authentication system with email verification, password reset, and 2FA
"""

import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Body, Depends, HTTPException, status, Request, Response, BackgroundTasks
from fastapi.responses import StreamingResponse
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from io import BytesIO

from config.settings import get_settings
from database.session import get_db, SessionLocal
from models.user import User
from services.hashing_service import hash_password, verify_password
from utils.password_policy import validate_password_strength
from services.jwt_service import (
    ACCESS_EXPIRE_MINUTES,
    REFRESH_EXPIRE_MINUTES,
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
    revoke_refresh_token,
    revoke_access_token,
    get_current_user,
)
from services.auth_service import AuthService
from auth.refresh_tokens import revoke_refresh_token_by_value, revoke_all_refresh_tokens
from services.runtime_metrics import get_runtime_metrics
from services.shared_security_state import (
    clear_shared_security_state_for_tests,
    increment_rate_limit_window,
)
from slowapi import Limiter
from slowapi.util import get_remote_address
from utils.structured_logging import log_event, log_auth_failure, log_admin_action, sanitize_for_log

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auth", tags=["Authentication"])
SETTINGS = get_settings()
COOKIE_SAMESITE = SETTINGS.cookie_samesite


def _cookie_secure() -> bool:
    return SETTINGS.is_production


def _set_auth_cookies(response: Response, access_token: str, refresh_token: str, csrf_token: str) -> None:
    response.set_cookie(
        "access_token",
        access_token,
        httponly=True,
        secure=_cookie_secure(),
        samesite=COOKIE_SAMESITE,
        max_age=ACCESS_EXPIRE_MINUTES * 60,
        path="/",
    )
    response.set_cookie(
        "refresh_token",
        refresh_token,
        httponly=True,
        secure=_cookie_secure(),
        samesite=COOKIE_SAMESITE,
        max_age=REFRESH_EXPIRE_MINUTES * 60,
        path="/",
    )
    response.set_cookie(
        "csrf_token",
        csrf_token,
        httponly=False,
        secure=_cookie_secure(),
        samesite=COOKIE_SAMESITE,
        max_age=REFRESH_EXPIRE_MINUTES * 60,
        path="/",
    )
    response.headers["Cache-Control"] = "no-store"


def _clear_auth_cookies(response: Response) -> None:
    response.delete_cookie("access_token", path="/")
    response.delete_cookie("refresh_token", path="/")
    response.delete_cookie("csrf_token", path="/")
    response.headers["Cache-Control"] = "no-store"


def _invalidate_user_sessions(
    request: Request,
    response: Response,
    *,
    db: Session,
    user: User,
    access_reason: str,
    refresh_reason: str,
) -> int:
    sessions_revoked = revoke_all_refresh_tokens(db, user.id)
    access_token = request.cookies.get("access_token") or (
        request.headers.get("Authorization", "").removeprefix("Bearer ").strip() or None
    )
    if access_token:
        try:
            revoke_access_token(db, access_token, reason=access_reason)
        except Exception:
            pass
    _clear_auth_cookies(response)
    _log_auth_event(
        "sessions_invalidated",
        user_id=user.id,
        reason=refresh_reason,
        sessions_revoked=sessions_revoked,
    )
    return sessions_revoked

is_testing = SETTINGS.testing

# Rate limiter (disabled in tests to avoid hangs)
limiter = Limiter(key_func=get_remote_address, storage_uri=SETTINGS.redis_url)

def rate_limit(rule: str):
    if is_testing:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)


_PASSWORD_RESET_WINDOW = timedelta(hours=1)
_PASSWORD_RESET_MAX_REQUESTS = 3


def _password_reset_request_is_throttled(request: Request) -> bool:
    forwarded_for = request.headers.get("X-Forwarded-For", "").split(",", 1)[0].strip()
    client_host = forwarded_for or (request.client.host if request.client else "") or "unknown"
    client_key = sanitize_for_log(client_host, max_len=128)
    count = increment_rate_limit_window(
        "password_reset_request",
        client_key,
        window_seconds=int(_PASSWORD_RESET_WINDOW.total_seconds()),
    )
    return count > _PASSWORD_RESET_MAX_REQUESTS


def _clear_password_reset_request_limits_for_tests() -> None:
    clear_shared_security_state_for_tests()


def record_login_success(user_id: int, ip_address: Optional[str]) -> None:
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            return
        AuthService(db).record_login_attempt(user, success=True, ip_address=ip_address)
    finally:
        db.close()


def _log_auth_event(action: str, *, level: int = logging.INFO, **fields) -> None:
    log_event(
        logger,
        "authentication",
        level=level,
        action=action,
        **fields,
    )
    if action == "failed_login":
        get_runtime_metrics().record_failed_auth()


# ===========================
# REQUEST/RESPONSE MODELS
# ===========================

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    password_confirm: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    totp_code: Optional[str] = None  # For 2FA


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenRevokeRequest(BaseModel):
    token: Optional[str] = None
    token_type: str = "access"  # access|refresh
    reason: Optional[str] = None


class UpdateEmailRequest(BaseModel):
    new_email: EmailStr
    password: str


class UpdatePasswordRequest(BaseModel):
    current_password: str
    new_password: str


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
    csrf_token: Optional[str] = None


def _extract_bearer_token(request: Request) -> Optional[str]:
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.lower().startswith("bearer "):
        return None
    token = auth_header.split(" ", 1)[1].strip()
    return token or None


# ===========================
# REGISTRATION & LOGIN
# ===========================

@router.post("/register", response_model=dict, status_code=status.HTTP_201_CREATED)
@rate_limit("5/hour")  # Prevent abuse
async def register(
    request: Request,
    payload: RegisterRequest,
    response: Response,
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
        password_error = validate_password_strength(payload.password)
        if password_error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=password_error
            )

        if payload.password != payload.password_confirm:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Passwords do not match"
            )

        # Create user
        user = User(
            email=payload.email,
            hashed_password=hash_password(payload.password),
            created_at=datetime.utcnow(),
            subscription_status="basic",
            email_verified=is_testing,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        # Send verification email (skipped in tests)
        email_sent = False
        if not is_testing:
            auth_service = AuthService(db)
            email_sent = auth_service.send_verification_email(user)

            if not email_sent:
                logger.warning("Failed to send verification email", extra={"user_id": user.id})

        _log_auth_event(
            "register",
            user_id=user.id,
            email=user.email,
            email_sent=email_sent,
        )

        # Always issue tokens so clients can proceed without a separate login step.
        # Email verification state is reflected in the /me endpoint.
        access_token = create_access_token(user)
        ip_address = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent")
        refresh_token = create_refresh_token(
            user,
            db,
            ip_address=ip_address,
            user_agent=user_agent,
        )
        csrf_token = secrets.token_urlsafe(32)
        _set_auth_cookies(response, access_token, refresh_token, csrf_token)

        message = (
            "Registration successful."
            if is_testing
            else "Registration successful. Please check your email to verify your account."
        )
        return {
            "status": "ok",
            "message": message,
            "email": user.email,
            "email_sent": email_sent,
            "user_id": user.id,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Registration error: %s", sanitize_for_log(str(e)))
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Registration failed"
        )


@router.post("/login", response_model=TokenResponse)
@rate_limit("10/minute")  # Prevent brute force
async def login(
    request: Request,
    payload: LoginRequest,
    background_tasks: BackgroundTasks,
    response: Response,
    db: Session = Depends(get_db)
):
    """
    Login with email and password (and optional 2FA code)
    """
    try:
        # Get user
        user: Optional[User] = db.query(User).filter(User.email == payload.email).first()

        # Check lockout BEFORE password verification to prevent timing-based enumeration.
        # A locked account returns 423 regardless of whether the password is correct.
        if user:
            auth_service = AuthService(db)
            if auth_service.is_account_locked(user):
                raise HTTPException(
                    status_code=status.HTTP_423_LOCKED,
                    detail="Account locked due to too many failed login attempts. Try again later."
                )

        is_valid = False
        if user:
            is_valid = await run_in_threadpool(
                verify_password,
                payload.password,
                user.hashed_password
            )

        if not user or not is_valid:
            # Record failed attempt
            if user:
                ip_address = request.client.host if request.client else None
                auth_service.record_login_attempt(user, success=False, ip_address=ip_address)
            _log_auth_event(
                "failed_login",
                level=logging.WARNING,
                email=payload.email,
                ip_address=request.client.host if request.client else None,
                reason="invalid_credentials",
            )

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials"
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
                # Raise 401 so the client knows to show the 2FA prompt.
                # A 200 response here would confirm the password was valid (oracle).
                raise HTTPException(
                    status_code=401,
                    detail={"requires_2fa": True, "message": "Two-factor authentication required"},
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
                _log_auth_event(
                    "failed_login",
                    level=logging.WARNING,
                    user_id=user.id,
                    ip_address=ip_address,
                    reason="invalid_2fa",
                )
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid 2FA code"
                )

        ip_address = request.client.host if request.client else None
        background_tasks.add_task(record_login_success, user.id, ip_address)

        # Admin status is managed via DB only — use management CLI to promote users

        _log_auth_event(
            "login",
            user_id=user.id,
            email=user.email,
            ip_address=ip_address,
            two_factor_enabled=user.has_2fa_enabled,
        )

        access_token = create_access_token(user)
        user_agent = request.headers.get("user-agent")
        refresh_token = create_refresh_token(
            user,
            db,
            ip_address=ip_address,
            user_agent=user_agent,
        )
        csrf_token = secrets.token_urlsafe(32)
        _set_auth_cookies(response, access_token, refresh_token, csrf_token)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            requires_2fa=False,
            csrf_token=csrf_token
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Login error: %s", sanitize_for_log(str(e)))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    request: Request,
    response: Response,
    payload: Optional[RefreshRequest] = Body(default=None),
    db: Session = Depends(get_db),
):
    """Refresh access token using cookie, Bearer, or request-body refresh token."""
    try:
        refresh_token_value = request.cookies.get("refresh_token")
        if not refresh_token_value:
            refresh_token_value = _extract_bearer_token(request)
        if not refresh_token_value and payload is not None:
            refresh_token_value = payload.refresh_token.strip() or None
        if not refresh_token_value:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token missing"
            )

        token_data = verify_refresh_token(refresh_token_value, db)
        user = db.query(User).filter(User.id == int(token_data.get("sub"))).first()

        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token"
            )

        access_token = create_access_token(user)
        ip_address = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent")
        refresh_token = create_refresh_token(
            user,
            db,
            ip_address=ip_address,
            user_agent=user_agent,
        )
        new_jti = verify_refresh_token(refresh_token).get("jti")
        old_jti = token_data.get("jti")
        if old_jti:
            revoke_refresh_token(db, old_jti, replaced_by_jti=new_jti)
        csrf_token = secrets.token_urlsafe(32)
        _set_auth_cookies(response, access_token, refresh_token, csrf_token)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            csrf_token=csrf_token,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Token refresh error: %s", sanitize_for_log(str(e)))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )


@router.post("/logout")
async def logout(request: Request, response: Response, db: Session = Depends(get_db)):
    access_token = request.cookies.get("access_token") or (
        request.headers.get("Authorization", "").removeprefix("Bearer ").strip() or None
    )
    if access_token:
        try:
            revoke_access_token(db, access_token, reason="logout")
        except Exception:
            pass
    refresh_token = request.cookies.get("refresh_token")
    if refresh_token:
        try:
            revoke_refresh_token_by_value(db, refresh_token, reason="logout")
        except Exception:
            pass
    response.delete_cookie("access_token", path="/")
    response.delete_cookie("refresh_token", path="/")
    response.delete_cookie("csrf_token", path="/")
    _log_auth_event("logout")
    return {"status": "ok"}


@router.post("/revoke-token")
async def revoke_token(
    request: Request,
    payload: Optional[TokenRevokeRequest] = Body(default=None),
    db: Session = Depends(get_db),
):
    """
    Revoke an access or refresh token and blacklist its JTI.
    """
    token_value = payload.token if payload else None
    token_type = (payload.token_type if payload else "access").strip().lower()
    reason = (payload.reason if payload else None) or "manual"

    if not token_value:
        auth_header = request.headers.get("Authorization", "")
        if auth_header.lower().startswith("bearer "):
            token_value = auth_header.split(" ", 1)[1].strip()

    if not token_value:
        if token_type == "refresh":
            token_value = request.cookies.get("refresh_token")
        else:
            token_value = request.cookies.get("access_token")

    if not token_value:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing token")

    if token_type not in {"access", "refresh"}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="token_type must be access or refresh")

    if token_type == "refresh":
        token_data = verify_refresh_token(token_value, db)
        jti = token_data.get("jti")
        if jti:
            revoke_refresh_token(db, jti)
    else:
        token_data = revoke_access_token(db, token_value, reason=reason)
        jti = token_data.get("jti")

    _log_auth_event(
        "token_revoked",
        token_type=token_type,
        user_id=token_data.get("sub"),
        jti_present=bool(token_data.get("jti")),
    )
    return {"status": "revoked", "token_type": token_type}


@router.get("/me")
async def get_current_user_info(current_user: User = Depends(get_current_user)):
    """Get current user information"""
    return {
        "id": current_user.id,
        "email": current_user.email,
        "is_active": current_user.is_active,
        "account_status": "active" if current_user.is_active else "inactive",
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
        logger.error("Email verification error: %s", sanitize_for_log(str(e)))
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
        logger.error("Resend verification error: %s", sanitize_for_log(str(e)))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to resend verification email"
        )


@router.post("/update-email")
@limiter.limit("5/hour")
async def update_email(
    request: Request,
    response: Response,
    payload: UpdateEmailRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update account email after verifying password.
    New tokens are set via Set-Cookie only — never returned in the JSON body.
    The previous access token is revoked immediately.
    """
    try:
        if not verify_password(payload.password, current_user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid password"
            )

        new_email = payload.new_email.strip().lower()
        if new_email == current_user.email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="New email must be different"
            )

        existing = db.query(User).filter(User.email == new_email).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use"
            )

        current_user.email = new_email
        current_user.email_verified = False
        db.commit()
        db.refresh(current_user)

        if not is_testing:
            auth_service = AuthService(db)
            auth_service.send_verification_email(current_user)

        sessions_revoked = _invalidate_user_sessions(
            request,
            response,
            db=db,
            user=current_user,
            access_reason="email_change",
            refresh_reason="email_change",
        )

        return {
            "message": "Email updated successfully. Please log in again.",
            "sessions_revoked": sessions_revoked,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Email update error: %s", sanitize_for_log(str(e)))
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update email"
        )


@router.post("/update-password")
@limiter.limit("5/hour")
async def update_password(
    request: Request,
    response: Response,
    payload: UpdatePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update account password after verifying current password"""
    try:
        if not verify_password(payload.current_password, current_user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid current password"
            )

        password_error = validate_password_strength(payload.new_password)
        if password_error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=password_error
            )

        current_user.hashed_password = hash_password(payload.new_password)
        current_user.failed_login_attempts = 0
        current_user.account_locked_until = None
        db.commit()

        sessions_revoked = _invalidate_user_sessions(
            request,
            response,
            db=db,
            user=current_user,
            access_reason="password_change",
            refresh_reason="password_change",
        )

        return {
            "message": "Password updated successfully. Please log in again.",
            "sessions_revoked": sessions_revoked,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Password update error: %s", sanitize_for_log(str(e)))
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update password"
        )


@router.post("/logout-all")
async def logout_all(
    request: Request,
    response: Response,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke all refresh token sessions for the authenticated user."""
    count = revoke_all_refresh_tokens(db, current_user.id)
    # Also revoke the current access token
    access_token = request.cookies.get("access_token") or (
        request.headers.get("Authorization", "").removeprefix("Bearer ").strip() or None
    )
    if access_token:
        try:
            revoke_access_token(db, access_token, reason="logout_all")
        except Exception:
            pass
    _clear_auth_cookies(response)
    _log_auth_event("logout_all", user_id=current_user.id, sessions_revoked=count)
    return {"status": "ok", "sessions_revoked": count}


# ===========================
# PASSWORD RESET
# ===========================

@router.post("/password-reset/request")
async def request_password_reset(
    request: Request,
    payload: PasswordResetRequestModel,
    db: Session = Depends(get_db)
):
    """Request password reset email"""
    generic_response = {
        "message": "If the email exists, a password reset link has been sent"
    }
    try:
        if _password_reset_request_is_throttled(request):
            get_runtime_metrics().record_rate_limited()
            _log_auth_event(
                "password_reset_request_throttled",
                level=logging.WARNING,
                ip_address=sanitize_for_log(
                    request.headers.get("X-Forwarded-For", "").split(",", 1)[0].strip()
                    or (request.client.host if request.client else "unknown"),
                    128,
                ),
            )
            return generic_response

        auth_service = AuthService(db)
        # Always returns success to prevent email enumeration
        auth_service.request_password_reset(payload.email)

        return generic_response

    except Exception as e:
        logger.error("Password reset request error: %s", sanitize_for_log(str(e)))
        # Don't reveal errors to prevent enumeration
        return generic_response


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
        logger.error("Password reset confirm error: %s", sanitize_for_log(str(e)))
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
        logger.error("2FA setup error: %s", sanitize_for_log(str(e)))
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
        decrypted_secret = auth_service._decrypt_value(current_user.totp_secret)
        if not decrypted_secret:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="2FA not set up. Call /2fa/setup first"
            )
        totp = pyotp.TOTP(decrypted_secret)
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
        logger.error("QR code generation error: %s", sanitize_for_log(str(e)))
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
        logger.error("2FA verification error: %s", sanitize_for_log(str(e)))
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
        logger.error("2FA disable error: %s", sanitize_for_log(str(e)))
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
