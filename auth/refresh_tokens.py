"""
auth/refresh_tokens.py — Refresh token rotation with replay detection.

Design:
  - Refresh tokens are long-lived (default 14 days) but single-use.
  - Each use rotates to a new token and revokes the old one.
  - The token value itself is NEVER returned in a JSON body — only via HttpOnly cookie.
  - Tokens are persisted in auth_refresh_tokens for session management.
  - Replay detection: presenting a revoked refresh token immediately invalidates
    the replacement chain (theft detection via token binding).
  - logout() revokes the current refresh token.
  - logout_all() revokes ALL refresh tokens for the user.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional, Tuple

from fastapi import HTTPException, Request, Response, status
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from auth.token import ALGORITHM, blacklist_jti, _utcnow, _coerce_exp
from config.settings import get_settings
from models.auth_refresh_token import AuthRefreshToken
from models.user import User

logger = logging.getLogger(__name__)
SETTINGS = get_settings()

REFRESH_SECRET: str = SETTINGS.refresh_token_secret
REFRESH_EXPIRE_MINUTES: int = SETTINGS.refresh_token_expire_minutes
_ALLOWED_ALGORITHMS = [ALGORITHM]


# ── Creation ───────────────────────────────────────────────────────────────────
def create_refresh_token(
    user: User,
    db: Session,
    *,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> str:
    """
    Mint a signed refresh token and persist the session record.

    The token string is returned for the caller to set as HttpOnly cookie.
    It must never be placed in a JSON response body.
    """
    jti = uuid.uuid4().hex
    now = _utcnow()
    exp = now + timedelta(minutes=REFRESH_EXPIRE_MINUTES)

    payload = {
        "sub": str(user.id),
        "type": "refresh",
        "jti": jti,
        "iat": now,
        "nbf": now,
        "exp": exp,
    }
    token = jwt.encode(payload, REFRESH_SECRET, algorithm=ALGORITHM)

    db.add(
        AuthRefreshToken(
            user_id=user.id,
            token_jti=jti,
            ip_address=(ip_address or "")[:64],
            user_agent=(user_agent or "")[:512],
            issued_at=now,
            expires_at=exp,
        )
    )
    db.commit()
    return token


# ── Validation ─────────────────────────────────────────────────────────────────
def _decode_refresh_token(token: str) -> dict:
    """Raw decode — raises HTTP 401 on any structural failure."""
    try:
        payload = jwt.decode(token, REFRESH_SECRET, algorithms=_ALLOWED_ALGORITHMS)
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        ) from exc

    if payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Wrong token type")
    if not payload.get("jti") or not payload.get("sub"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Malformed refresh token")
    return payload


def _load_session(db: Session, jti: str) -> AuthRefreshToken:
    """Load the DB session record for a JTI, enforcing all validity checks."""
    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()

    if not session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown refresh token")

    if session.revoked_at is not None:
        # Replay detected — the original was already rotated.
        # Invalidate the replacement chain to contain a potential token theft.
        _invalidate_replacement_chain(db, session)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token reuse detected — all sessions invalidated",
        )

    if session.expires_at <= _utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")

    return session


def _invalidate_replacement_chain(db: Session, root: AuthRefreshToken) -> None:
    """
    Walk the replacement chain and revoke every node.

    This is the theft-detection response: if a previously rotated token is
    presented again, we assume the original holder's token was stolen. Revoke
    the entire chain to force re-authentication.
    """
    to_revoke = [root]
    visited = {root.token_jti}
    current = root

    for _ in range(50):  # depth cap — prevents infinite loop on corrupt data
        if not current.replaced_by_jti:
            break
        next_jti = current.replaced_by_jti
        if next_jti in visited:
            break
        visited.add(next_jti)
        next_session = (
            db.query(AuthRefreshToken)
            .filter(AuthRefreshToken.token_jti == next_jti)
            .first()
        )
        if not next_session:
            break
        to_revoke.append(next_session)
        current = next_session

    now = _utcnow()
    for s in to_revoke:
        if s.revoked_at is None:
            s.revoked_at = now
        blacklist_jti(
            db,
            jti=s.token_jti,
            token_type="refresh",
            expires_at=s.expires_at,
            user_id=s.user_id,
            reason="replay_detected",
        )

    db.commit()
    logger.warning(
        "refresh_token_replay_detected",
        extra={"user_id": root.user_id, "chain_length": len(to_revoke)},
    )


# ── Rotation ───────────────────────────────────────────────────────────────────
def rotate_refresh_token(
    db: Session,
    request: Request,
    response: Response,
    *,
    refresh_token_value: str,
) -> Tuple[str, str]:
    """
    Validate the presented refresh token, rotate it, and return new tokens.

    Returns (new_access_token_str, new_refresh_token_str).

    Callers MUST set the returned tokens via HttpOnly cookies — not in JSON.
    """
    from auth.token import create_access_token  # local import avoids circular dep

    payload = _decode_refresh_token(refresh_token_value)
    old_jti = payload["jti"]
    session = _load_session(db, old_jti)

    user = db.query(User).filter(User.id == session.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

    # Mint new tokens
    new_access = create_access_token(user)
    new_refresh = create_refresh_token(
        user,
        db,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    # Revoke old session (record replacement linkage for chain invalidation)
    new_payload = _decode_refresh_token(new_refresh)
    new_jti = new_payload["jti"]

    session.revoked_at = _utcnow()
    session.replaced_by_jti = new_jti
    blacklist_jti(
        db,
        jti=old_jti,
        token_type="refresh",
        expires_at=session.expires_at,
        user_id=session.user_id,
        reason="rotated",
    )
    db.commit()

    return new_access, new_refresh


# ── Logout ─────────────────────────────────────────────────────────────────────
def revoke_refresh_token_by_value(db: Session, token: str, *, reason: str = "logout") -> None:
    """Revoke the refresh token supplied (by JWT value)."""
    payload = _decode_refresh_token(token)
    jti = payload["jti"]
    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()
    if session and session.revoked_at is None:
        session.revoked_at = _utcnow()
        blacklist_jti(
            db,
            jti=jti,
            token_type="refresh",
            expires_at=session.expires_at,
            user_id=session.user_id,
            reason=reason,
        )
        db.commit()


def revoke_all_refresh_tokens(db: Session, user_id: int) -> int:
    """
    Revoke ALL active refresh tokens for user_id.

    Used by logout-all. Returns the count of sessions revoked.
    """
    sessions = (
        db.query(AuthRefreshToken)
        .filter(
            AuthRefreshToken.user_id == user_id,
            AuthRefreshToken.revoked_at.is_(None),
        )
        .all()
    )

    now = _utcnow()
    for s in sessions:
        s.revoked_at = now
        blacklist_jti(
            db,
            jti=s.token_jti,
            token_type="refresh",
            expires_at=s.expires_at,
            user_id=user_id,
            reason="logout_all",
        )

    db.commit()
    return len(sessions)


def get_active_sessions(db: Session, user_id: int) -> list:
    """Return metadata for all active sessions (no token values)."""
    sessions = (
        db.query(AuthRefreshToken)
        .filter(
            AuthRefreshToken.user_id == user_id,
            AuthRefreshToken.revoked_at.is_(None),
            AuthRefreshToken.expires_at > _utcnow(),
        )
        .order_by(AuthRefreshToken.issued_at.desc())
        .all()
    )
    return [
        {
            "id": s.id,
            "issued_at": s.issued_at.isoformat() if s.issued_at else None,
            "expires_at": s.expires_at.isoformat() if s.expires_at else None,
            "ip_address": s.ip_address,
            "user_agent": s.user_agent,
        }
        for s in sessions
    ]
