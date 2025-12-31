import os
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User

ACCESS_SECRET = os.getenv("ACCESS_TOKEN_SECRET", "dev_access_secret")
REFRESH_SECRET = os.getenv("REFRESH_TOKEN_SECRET", "dev_refresh_secret")
ALGORITHM = "HS256"
ACCESS_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
REFRESH_EXPIRE_MINUTES = int(os.getenv("REFRESH_TOKEN_EXPIRE_MINUTES", str(60 * 24 * 14)))

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


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


def get_current_user(db: Session = Depends(get_db), token: str = Depends(oauth2_scheme)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
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
