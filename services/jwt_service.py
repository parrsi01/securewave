import os
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
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
    claims = {"sub": str(user.id), "email": user.email, "type": "access"}
    return _create_token(claims, timedelta(minutes=ACCESS_EXPIRE_MINUTES), ACCESS_SECRET)


def create_refresh_token(user: User) -> str:
    claims = {"sub": str(user.id), "email": user.email, "type": "refresh"}
    return _create_token(claims, timedelta(minutes=REFRESH_EXPIRE_MINUTES), REFRESH_SECRET)


def decode_token(token: str, secret: str) -> dict:
    try:
        return jwt.decode(token, secret, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc


def verify_refresh_token(token: str) -> dict:
    payload = decode_token(token, REFRESH_SECRET)
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token type")
    return payload


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
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - safety net
        raise credentials_exception from exc

    user = db.query(User).filter(User.id == int(user_id)).first()
    if user is None:
        raise credentials_exception
    return user
