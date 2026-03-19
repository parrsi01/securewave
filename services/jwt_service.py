import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from database.session import get_db
from models.auth_refresh_token import AuthRefreshToken
from models.jwt_blacklist_token import JWTBlacklistToken
from models.user import User
from config.settings import get_settings
from services.shared_security_state import (
    get_refresh_session,
    is_token_revoked,
    register_refresh_session,
    remember_revoked_token,
    revoke_refresh_session as cache_revoke_refresh_session,
)

logger = logging.getLogger(__name__)
SETTINGS = get_settings()
ENVIRONMENT = SETTINGS.environment
ACCESS_SECRET = SETTINGS.access_token_secret
REFRESH_SECRET = SETTINGS.refresh_token_secret
ALGORITHM = "HS256"
ACCESS_EXPIRE_MINUTES = SETTINGS.access_token_expire_minutes
REFRESH_EXPIRE_MINUTES = SETTINGS.refresh_token_expire_minutes
REFRESH_SESSION_REQUIRED = SETTINGS.refresh_session_required

if SETTINGS.is_production:
    logger.info("JWT secrets validated for production environment")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


def _utcnow() -> datetime:
    return datetime.utcnow()


def _coerce_expiration(exp_claim) -> datetime:
    if isinstance(exp_claim, datetime):
        return exp_claim.replace(tzinfo=None)
    if isinstance(exp_claim, (int, float)):
        return datetime.utcfromtimestamp(exp_claim)
    if isinstance(exp_claim, str):
        try:
            return datetime.fromisoformat(exp_claim.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            pass
    return _utcnow() + timedelta(minutes=ACCESS_EXPIRE_MINUTES)


def _create_token(data: dict, expires_delta: timedelta, secret: str) -> str:
    to_encode = data.copy()
    issued_at = _utcnow()
    expire = issued_at + expires_delta
    to_encode.update(
        {
            "iat": issued_at,
            "nbf": issued_at,
            "exp": expire,
            "jti": to_encode.get("jti") or uuid.uuid4().hex,
        }
    )
    return jwt.encode(to_encode, secret, algorithm=ALGORITHM)


def create_access_token(user: User) -> str:
    claims = {"sub": str(user.id), "email": user.email, "type": "access", "jti": uuid.uuid4().hex}
    return _create_token(claims, timedelta(minutes=ACCESS_EXPIRE_MINUTES), ACCESS_SECRET)


def _persist_refresh_session(
    db: Session,
    *,
    user_id: int,
    jti: str,
    expires_at: datetime,
    ip_address: Optional[str],
    user_agent: Optional[str],
) -> None:
    session = AuthRefreshToken(
        user_id=user_id,
        token_jti=jti,
        ip_address=ip_address,
        user_agent=user_agent,
        issued_at=_utcnow(),
        expires_at=expires_at,
    )
    db.add(session)
    db.commit()
    register_refresh_session(
        token_jti=jti,
        user_id=user_id,
        expires_at=expires_at,
        issued_at=session.issued_at,
        ip_address=ip_address,
        user_agent=user_agent,
    )


def create_refresh_token(
    user: User,
    db: Optional[Session] = None,
    *,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> str:
    jti = uuid.uuid4().hex
    expires_delta = timedelta(minutes=REFRESH_EXPIRE_MINUTES)
    expires_at = _utcnow() + expires_delta
    claims = {
        "sub": str(user.id),
        "email": user.email,
        "type": "refresh",
        "jti": jti,
    }
    token = _create_token(claims, expires_delta, REFRESH_SECRET)
    if db is not None:
        _persist_refresh_session(
            db,
            user_id=user.id,
            jti=jti,
            expires_at=expires_at,
            ip_address=ip_address,
            user_agent=user_agent,
        )
    return token


def decode_token(token: str, secret: str) -> dict:
    try:
        return jwt.decode(token, secret, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc


def is_token_jti_revoked(db: Session, token_jti: Optional[str]) -> bool:
    if not token_jti:
        return False
    if is_token_revoked(token_jti):
        return True
    existing = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.token_jti == token_jti)
        .first()
    )
    if existing:
        remember_revoked_token(
            token_jti=existing.token_jti,
            token_type=existing.token_type,
            expires_at=existing.expires_at,
            user_id=existing.user_id,
            reason=existing.reason,
        )
        return True
    return False


def blacklist_token_jti(
    db: Session,
    *,
    token_jti: str,
    token_type: str,
    expires_at: datetime,
    user_id: Optional[int] = None,
    reason: Optional[str] = None,
) -> None:
    existing = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.token_jti == token_jti)
        .first()
    )
    if existing:
        remember_revoked_token(
            token_jti=existing.token_jti,
            token_type=existing.token_type,
            expires_at=existing.expires_at,
            user_id=existing.user_id,
            reason=existing.reason,
        )
        return

    db.add(
        JWTBlacklistToken(
            user_id=user_id,
            token_jti=token_jti,
            token_type=(token_type or "access")[:16],
            reason=(reason or "manual")[:128],
            expires_at=expires_at,
        )
    )
    db.commit()
    remember_revoked_token(
        token_jti=token_jti,
        token_type=token_type,
        expires_at=expires_at,
        user_id=user_id,
        reason=reason,
    )


def revoke_access_token(db: Session, token: str, *, reason: str = "manual") -> dict:
    payload = decode_token(token, ACCESS_SECRET)
    if payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Token is not an access token")
    token_jti = payload.get("jti")
    if not token_jti:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Malformed token")

    blacklist_token_jti(
        db,
        token_jti=token_jti,
        token_type="access",
        expires_at=_coerce_expiration(payload.get("exp")),
        user_id=int(payload.get("sub")) if payload.get("sub") else None,
        reason=reason,
    )
    return payload


def verify_refresh_token(token: str, db: Optional[Session] = None) -> dict:
    payload = decode_token(token, REFRESH_SECRET)
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token type")

    jti = payload.get("jti")
    if not jti:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Malformed refresh token")

    if db is None:
        return payload

    if is_token_jti_revoked(db, jti):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token was revoked")

    cached_session = get_refresh_session(jti)
    if cached_session is not None:
        if cached_session.get("revoked_at"):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token was revoked")
        if _coerce_expiration(cached_session.get("expires_at")) <= _utcnow():
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")
        return payload

    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()
    if not session:
        if REFRESH_SESSION_REQUIRED:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown refresh token session")
        return payload
    if session.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token was revoked")
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
    return payload


def revoke_refresh_token(db: Session, token_jti: str, *, replaced_by_jti: Optional[str] = None) -> None:
    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == token_jti).first()
    if not session:
        return
    if session.revoked_at is None:
        session.revoked_at = _utcnow()
    if replaced_by_jti:
        session.replaced_by_jti = replaced_by_jti
    db.add(session)

    # Keep blacklist table in sync so middleware can reject the refresh token too.
    blacklist_token_jti(
        db,
        token_jti=token_jti,
        token_type="refresh",
        expires_at=session.expires_at,
        user_id=session.user_id,
        reason="rotated" if replaced_by_jti else "revoked",
    )
    db.commit()
    cache_revoke_refresh_session(
        token_jti=token_jti,
        user_id=session.user_id,
        expires_at=session.expires_at,
        revoked_at=session.revoked_at,
        replaced_by_jti=session.replaced_by_jti,
    )


def purge_expired_blacklist_tokens(db: Session) -> int:
    now = _utcnow()
    deleted = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.expires_at <= now)
        .delete(synchronize_session=False)
    )
    db.commit()
    return int(deleted or 0)


def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
    token: Optional[str] = Depends(oauth2_scheme),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        token = request.cookies.get("access_token")
    if not token:
        raise credentials_exception
    try:
        payload = decode_token(token, ACCESS_SECRET)
        if payload.get("type") != "access":
            raise credentials_exception
        user_id: Optional[str] = payload.get("sub")
        if user_id is None:
            raise credentials_exception
        if is_token_jti_revoked(db, payload.get("jti")):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token revoked")
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - safety net
        raise credentials_exception from exc

    user = db.query(User).filter(User.id == int(user_id)).first()
    if user is None:
        raise credentials_exception
    return user
