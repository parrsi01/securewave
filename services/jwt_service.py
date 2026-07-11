import os
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
import jwt
from sqlalchemy.orm import Session

from database.session import get_db
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

if ENVIRONMENT == "production":
    logger.info("JWT secrets validated for production environment")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


def _create_token(data: dict, expires_delta: timedelta, secret: str) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + expires_delta
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, secret, algorithm=ALGORITHM)


def create_access_token(user: User) -> str:
    claims = {
        "sub": str(user.id),
        "email": user.email,
        "type": "access",
        "ver": int(user.auth_token_version or 0),
    }
    return _create_token(claims, timedelta(minutes=ACCESS_EXPIRE_MINUTES), ACCESS_SECRET)


def create_refresh_token(user: User) -> str:
    claims = {
        "sub": str(user.id),
        "email": user.email,
        "type": "refresh",
        "ver": int(user.auth_token_version or 0),
    }
    return _create_token(claims, timedelta(minutes=REFRESH_EXPIRE_MINUTES), REFRESH_SECRET)


def decode_token(token: str, secret: str) -> dict:
    try:
        return jwt.decode(token, secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc


def verify_refresh_token(token: str) -> dict:
    payload = decode_token(token, REFRESH_SECRET)
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token type")
    return payload


def token_version_matches(payload: dict, user: User) -> bool:
    """Return whether a token belongs to the user's current auth generation.

    Tokens issued before the version claim was introduced are treated as
    version zero so they remain valid until the first explicit invalidation.
    """
    try:
        token_version = int(payload.get("ver", 0))
        user_version = int(user.auth_token_version or 0)
    except (TypeError, ValueError):
        return False
    return token_version == user_version


def get_optional_current_user(
    request: Request,
    db: Session = Depends(get_db),
    token: Optional[str] = Depends(oauth2_scheme),
) -> Optional[User]:
    """Resolve an access token when supplied without requiring anonymous callers."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        token = request.cookies.get("access_token")
    if not token:
        return None
    try:
        payload = decode_token(token, ACCESS_SECRET)
        if payload.get("type") != "access":
            raise credentials_exception
        user_id: Optional[str] = payload.get("sub")
        if user_id is None:
            raise credentials_exception
        user_id_value = int(user_id)
    except HTTPException:
        raise
    except (TypeError, ValueError) as exc:
        raise credentials_exception from exc

    user = db.query(User).filter(User.id == user_id_value).first()
    if user is None or not user.is_active or not token_version_matches(payload, user):
        raise credentials_exception
    return user


def get_current_user(
    user: Optional[User] = Depends(get_optional_current_user),
) -> User:
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
