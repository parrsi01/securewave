"""Compatibility layer over the shared JWT service implementation."""

from __future__ import annotations

from typing import List, Optional

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services import jwt_service

ALGORITHM = jwt_service.ALGORITHM
ACCESS_SECRET: str = jwt_service.ACCESS_SECRET
ACCESS_EXPIRE_MINUTES: int = jwt_service.ACCESS_EXPIRE_MINUTES
oauth2_scheme = jwt_service.oauth2_scheme


class Scope:
    USER = jwt_service.Scope.USER
    ADMIN = jwt_service.Scope.ADMIN
    VPN = jwt_service.Scope.VPN


def _utcnow():
    return jwt_service._utcnow()


def _coerce_exp(exp_claim):
    return jwt_service._coerce_expiration(exp_claim)


def create_access_token(user: User) -> str:
    return jwt_service.create_access_token(user)


def decode_access_token(token: str) -> dict:
    payload = jwt_service.decode_token(token, ACCESS_SECRET)
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
    return jwt_service.is_token_jti_revoked(db, jti)


def blacklist_jti(
    db: Session,
    *,
    jti: str,
    token_type: str,
    expires_at,
    user_id: Optional[int] = None,
    reason: str = "revoked",
) -> None:
    jwt_service.blacklist_token_jti(
        db,
        token_jti=jti,
        token_type=token_type,
        expires_at=expires_at,
        user_id=user_id,
        reason=reason,
    )


def revoke_access_token(db: Session, token: str, *, reason: str = "logout") -> None:
    jwt_service.revoke_access_token(db, token, reason=reason)


def purge_expired_blacklist(db: Session) -> int:
    return jwt_service.purge_expired_blacklist_tokens(db)


def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
    bearer_token: Optional[str] = Depends(oauth2_scheme),
) -> User:
    return jwt_service.get_current_user(request=request, db=db, token=bearer_token)


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Insufficient privileges",
        )
    return current_user


def require_scope(scope: str):
    def _check(
        request: Request,
        db: Session = Depends(get_db),
        bearer_token: Optional[str] = Depends(oauth2_scheme),
    ) -> User:
        token = bearer_token or request.cookies.get("access_token")
        if not token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required",
            )

        payload = decode_access_token(token)
        if is_jti_revoked(db, payload["jti"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token revoked",
            )

        token_scopes: List[str] = payload.get("scopes", [])
        if scope not in token_scopes:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Scope '{scope}' required",
            )

        user = db.query(User).filter(User.id == int(payload["sub"])).first()
        if user is None or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
            )
        return user

    return _check
