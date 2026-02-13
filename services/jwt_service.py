import os
import logging
import secrets
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

logger = logging.getLogger(__name__)

# Load JWT secrets
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


def _load_secret(name: str) -> str:
    secret = os.getenv(name)
    if secret:
        return secret
    if ENVIRONMENT == "production":
        raise RuntimeError(
            f"CRITICAL SECURITY ERROR: Production requires secure {name}. "
            "Generate a secret with: python -c \"import secrets; print(secrets.token_urlsafe(64))\""
        )
    generated = secrets.token_urlsafe(32)
    logger.warning(
        "WARNING: %s not set; generated an ephemeral development secret. "
        "Set %s for stable tokens across restarts.",
        name,
        name,
    )
    return generated


ACCESS_SECRET = _load_secret("ACCESS_TOKEN_SECRET")
REFRESH_SECRET = _load_secret("REFRESH_TOKEN_SECRET")
ALGORITHM = "HS256"
ACCESS_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
REFRESH_EXPIRE_MINUTES = int(os.getenv("REFRESH_TOKEN_EXPIRE_MINUTES", str(60 * 24 * 14)))
REFRESH_SESSION_REQUIRED = os.getenv(
    "REFRESH_SESSION_REQUIRED",
    "true" if ENVIRONMENT == "production" else "false",
).lower() == "true"

if ENVIRONMENT == "production":
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
    return (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.token_jti == token_jti)
        .first()
        is not None
    )


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

    session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()
    if not session:
        if REFRESH_SESSION_REQUIRED:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown refresh token session")
        return payload
    if session.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token was revoked")
    if session.expires_at <= _utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")
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
