"""Refresh-token session helpers layered on the shared JWT service."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Optional, Tuple

from fastapi import HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from auth.token import _utcnow, blacklist_jti, create_access_token
from models.auth_refresh_token import AuthRefreshToken
from models.user import User
from services import jwt_service
from services.shared_security_state import (
    get_refresh_session,
    register_refresh_session,
    revoke_refresh_session as cache_revoke_refresh_session,
)

logger = logging.getLogger(__name__)

REFRESH_SECRET: str = jwt_service.REFRESH_SECRET
REFRESH_EXPIRE_MINUTES: int = jwt_service.REFRESH_EXPIRE_MINUTES


def create_refresh_token(
    user: User,
    db: Session,
    *,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> str:
    return jwt_service.create_refresh_token(
        user,
        db,
        ip_address=ip_address,
        user_agent=user_agent,
    )


def _decode_refresh_token(token: str) -> dict:
    payload = jwt_service.decode_token(token, REFRESH_SECRET)
    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Wrong token type",
        )
    if not payload.get("jti") or not payload.get("sub"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed refresh token",
        )
    return payload


def _load_session(db: Session, jti: str) -> AuthRefreshToken:
    cached = get_refresh_session(jti)
    if cached is not None:
        cached_exp = cached.get("expires_at")
        if isinstance(cached_exp, str):
            try:
                exp_dt = datetime.fromisoformat(cached_exp)
            except ValueError:
                exp_dt = None
            if exp_dt is not None and exp_dt.tzinfo is not None:
                exp_dt = exp_dt.astimezone().replace(tzinfo=None)
            if exp_dt is not None and exp_dt <= _utcnow():
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Refresh token expired",
                )

    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()

    if not session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown refresh token")

    if session.revoked_at is not None:
        _invalidate_replacement_chain(db, session)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token reuse detected — all sessions invalidated",
        )

    if session.expires_at <= _utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")

    register_refresh_session(
        token_jti=session.token_jti,
        user_id=session.user_id,
        expires_at=session.expires_at,
        issued_at=session.issued_at,
        ip_address=session.ip_address,
        user_agent=session.user_agent,
        revoked_at=session.revoked_at,
        replaced_by_jti=session.replaced_by_jti,
    )
    return session


def _invalidate_replacement_chain(db: Session, root: AuthRefreshToken) -> None:
    to_revoke = [root]
    visited = {root.token_jti}
    current = root

    for _ in range(50):
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
    for session in to_revoke:
        if session.revoked_at is None:
            session.revoked_at = now
        blacklist_jti(
            db,
            jti=session.token_jti,
            token_type="refresh",
            expires_at=session.expires_at,
            user_id=session.user_id,
            reason="replay_detected",
        )
        cache_revoke_refresh_session(
            token_jti=session.token_jti,
            user_id=session.user_id,
            expires_at=session.expires_at,
            revoked_at=session.revoked_at,
            replaced_by_jti=session.replaced_by_jti,
        )

    db.commit()
    logger.warning(
        "refresh_token_replay_detected",
        extra={"user_id": root.user_id, "chain_length": len(to_revoke)},
    )


def rotate_refresh_token(
    db: Session,
    request: Request,
    response: Response,
    *,
    refresh_token_value: str,
) -> Tuple[str, str]:
    del response

    payload = _decode_refresh_token(refresh_token_value)
    old_jti = payload["jti"]
    session = _load_session(db, old_jti)

    user = db.query(User).filter(User.id == session.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

    new_access = create_access_token(user)
    new_refresh = create_refresh_token(
        user,
        db,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    new_payload = _decode_refresh_token(new_refresh)
    session.revoked_at = _utcnow()
    session.replaced_by_jti = new_payload["jti"]
    blacklist_jti(
        db,
        jti=old_jti,
        token_type="refresh",
        expires_at=session.expires_at,
        user_id=session.user_id,
        reason="rotated",
    )
    db.commit()
    cache_revoke_refresh_session(
        token_jti=old_jti,
        user_id=session.user_id,
        expires_at=session.expires_at,
        revoked_at=session.revoked_at,
        replaced_by_jti=session.replaced_by_jti,
    )

    return new_access, new_refresh


def revoke_refresh_token_by_value(db: Session, token: str, *, reason: str = "logout") -> None:
    payload = _decode_refresh_token(token)
    jwt_service.revoke_refresh_token(db, payload["jti"], reason=reason)


def revoke_all_refresh_tokens(db: Session, user_id: int) -> int:
    sessions = (
        db.query(AuthRefreshToken)
        .filter(
            AuthRefreshToken.user_id == user_id,
            AuthRefreshToken.revoked_at.is_(None),
        )
        .all()
    )

    now = _utcnow()
    for session in sessions:
        session.revoked_at = now
        blacklist_jti(
            db,
            jti=session.token_jti,
            token_type="refresh",
            expires_at=session.expires_at,
            user_id=user_id,
            reason="logout_all",
        )
        cache_revoke_refresh_session(
            token_jti=session.token_jti,
            user_id=session.user_id,
            expires_at=session.expires_at,
            revoked_at=session.revoked_at,
            replaced_by_jti=session.replaced_by_jti,
        )

    db.commit()
    return len(sessions)


def get_active_sessions(db: Session, user_id: int) -> list:
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
            "id": session.id,
            "issued_at": session.issued_at.isoformat() if session.issued_at else None,
            "expires_at": session.expires_at.isoformat() if session.expires_at else None,
            "ip_address": session.ip_address,
            "user_agent": session.user_agent,
        }
        for session in sessions
    ]
