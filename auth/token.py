"""
auth/token.py — JWT access token creation, validation, and scope enforcement.

Design:
  - Short-lived access tokens (default 15 min, hard-cap 60 min in prod)
  - Scopes embedded as list claim: ["user"], ["admin"], etc.
  - Algorithm pinned to HS256; algorithm header validated on decode to block alg:none
  - All decodes require explicit algorithm list — no auto-detection
  - Constant-time JTI revocation check (single indexed DB query)
  - Tokens are NEVER returned in JSON bodies — callers use _set_auth_cookies()
"""

from __future__ import annotations

import hmac
import logging
import uuid
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from config.settings import get_settings
from database.session import get_db
from models.jwt_blacklist_token import JWTBlacklistToken
from models.user import User
from services.shared_security_state import is_token_revoked, remember_revoked_token

logger = logging.getLogger(__name__)
SETTINGS = get_settings()

# ── Constants ──────────────────────────────────────────────────────────────────
ALGORITHM = "HS256"
_ALLOWED_ALGORITHMS = [ALGORITHM]

ACCESS_SECRET: str = SETTINGS.access_token_secret
_ACCESS_EXPIRE_MINUTES: int = SETTINGS.access_token_expire_minutes
_ACCESS_EXPIRE_MINUTES_MAX: int = 60  # hard cap regardless of settings

# Effective expiry — respects the hard cap in production
ACCESS_EXPIRE_MINUTES: int = (
    min(_ACCESS_EXPIRE_MINUTES, _ACCESS_EXPIRE_MINUTES_MAX)
    if SETTINGS.is_production
    else _ACCESS_EXPIRE_MINUTES
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


# ── Scopes ─────────────────────────────────────────────────────────────────────
class Scope:
    USER = "user"
    ADMIN = "admin"
    VPN = "vpn"


def _scopes_for(user: User) -> List[str]:
    scopes = [Scope.USER]
    if user.is_admin:
        scopes.append(Scope.ADMIN)
    return scopes


# ── Internal helpers ───────────────────────────────────────────────────────────
def _utcnow() -> datetime:
    return datetime.utcnow()


def _coerce_exp(exp_claim) -> datetime:
    """Normalise the exp claim to a naive UTC datetime."""
    if isinstance(exp_claim, datetime):
        return exp_claim.replace(tzinfo=None)
    if isinstance(exp_claim, (int, float)):
        return datetime.utcfromtimestamp(exp_claim)
    return _utcnow()


# ── Token creation ─────────────────────────────────────────────────────────────
def create_access_token(user: User) -> str:
    """
    Mint a signed access token for *user*.

    Claims:
      sub   — str(user.id)
      email — user.email  (informational; not for auth decisions)
      type  — "access"
      scopes— ["user"] or ["user","admin"]
      jti   — unique token ID (for revocation)
      iat, nbf, exp — standard time claims
    """
    now = _utcnow()
    exp = now + timedelta(minutes=ACCESS_EXPIRE_MINUTES)
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "type": "access",
        "scopes": _scopes_for(user),
        "jti": uuid.uuid4().hex,
        "iat": now,
        "nbf": now,
        "exp": exp,
    }
    return jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)


# ── Token validation ───────────────────────────────────────────────────────────
def decode_access_token(token: str) -> dict:
    """
    Decode and structurally validate an access token.

    Raises HTTP 401 on any failure (expired, tampered, wrong type, alg mismatch).
    Does NOT check the revocation list — callers must call is_revoked() separately
    or use get_current_user() which combines both.
    """
    try:
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=_ALLOWED_ALGORITHMS)
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not payload.get("jti"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed token: missing jti",
        )
    return payload


def is_jti_revoked(db: Session, jti: str) -> bool:
    """Single indexed query; constant-time at the DB layer."""
    if is_token_revoked(jti):
        return True
    existing = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.token_jti == jti)
        .first()
    )
    if existing:
        remember_revoked_token(
            token_jti=jti,
            token_type=existing.token_type,
            expires_at=existing.expires_at,
            user_id=existing.user_id,
            reason=existing.reason,
        )
        return True
    return False


def blacklist_jti(
    db: Session,
    *,
    jti: str,
    token_type: str,
    expires_at: datetime,
    user_id: Optional[int] = None,
    reason: str = "revoked",
) -> None:
    """Idempotent — safe to call multiple times for the same JTI."""
    exists = (
        db.query(JWTBlacklistToken.id)
        .filter(JWTBlacklistToken.token_jti == jti)
        .first()
    )
    if exists:
        remember_revoked_token(
            token_jti=jti,
            token_type=token_type,
            expires_at=expires_at,
            user_id=user_id,
            reason=reason,
        )
        return
    db.add(
        JWTBlacklistToken(
            user_id=user_id,
            token_jti=jti,
            token_type=token_type[:16],
            reason=reason[:128],
            expires_at=expires_at,
        )
    )
    db.commit()
    remember_revoked_token(
        token_jti=jti,
        token_type=token_type,
        expires_at=expires_at,
        user_id=user_id,
        reason=reason,
    )


def revoke_access_token(db: Session, token: str, *, reason: str = "logout") -> None:
    """Revoke an access token by blacklisting its JTI."""
    payload = decode_access_token(token)
    blacklist_jti(
        db,
        jti=payload["jti"],
        token_type="access",
        expires_at=_coerce_exp(payload.get("exp")),
        user_id=int(payload["sub"]) if payload.get("sub") else None,
        reason=reason,
    )


def purge_expired_blacklist(db: Session) -> int:
    """Remove blacklist entries whose tokens have already expired. Cron-friendly."""
    deleted = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.expires_at <= _utcnow())
        .delete(synchronize_session=False)
    )
    db.commit()
    return int(deleted or 0)


# ── FastAPI dependencies ───────────────────────────────────────────────────────
def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
    bearer_token: Optional[str] = Depends(oauth2_scheme),
) -> User:
    """
    FastAPI dependency — resolves the authenticated User.

    Token source priority:
      1. Authorization: Bearer <token> header
      2. access_token HttpOnly cookie
    """
    token = bearer_token or request.cookies.get("access_token")
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_access_token(token)

    if is_jti_revoked(db, payload["jti"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked",
        )

    user = db.query(User).filter(User.id == int(payload["sub"])).first()
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )
    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """
    FastAPI dependency — requires admin scope.

    Use as:  admin: User = Depends(require_admin)

    Raises 403 (not 401) to avoid disclosing endpoint existence to unauthenticated callers
    who already passed get_current_user but lack admin scope.
    """
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Insufficient privileges",
        )
    return current_user


def require_scope(scope: str):
    """
    FastAPI dependency factory — requires a specific scope in the token claims.

    Usage:
        @router.get("/vpn/config")
        async def vpn_config(user: User = Depends(require_scope(Scope.VPN))):
            ...
    """
    def _check(
        request: Request,
        db: Session = Depends(get_db),
        bearer_token: Optional[str] = Depends(oauth2_scheme),
    ) -> User:
        token = bearer_token or request.cookies.get("access_token")
        if not token:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")

        payload = decode_access_token(token)

        if is_jti_revoked(db, payload["jti"]):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token revoked")

        token_scopes: List[str] = payload.get("scopes", [])
        if scope not in token_scopes:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Scope '{scope}' required",
            )

        user = db.query(User).filter(User.id == int(payload["sub"])).first()
        if user is None or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
        return user

    return _check
