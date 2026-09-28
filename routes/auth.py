"""Minimal app authentication API.

The Linux app needs a small, predictable auth surface:

- register with any valid email address and an 8+ character password
- login immediately after registration
- inspect the current account
- logout by invalidating the current token generation
"""

import os
import secrets
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.hashing_service import hash_password, verify_password
from services.jwt_service import (
    ACCESS_EXPIRE_MINUTES,
    REFRESH_EXPIRE_MINUTES,
    create_access_token,
    create_refresh_token,
    get_current_user,
)
from slowapi import Limiter
from slowapi.util import get_remote_address


router = APIRouter(prefix="/api/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address)
IS_TESTING = os.getenv("TESTING", "").lower() == "true"
COOKIE_SAMESITE = os.getenv("COOKIE_SAMESITE", "lax")


def rate_limit(rule: str):
    if IS_TESTING:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)


def _cookie_secure() -> bool:
    return os.getenv("ENVIRONMENT", "development") == "production"


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


def _token_response(user: User, response: Response) -> dict:
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)
    csrf_token = secrets.token_urlsafe(32)
    _set_auth_cookies(response, access_token, refresh_token, csrf_token)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "csrf_token": csrf_token,
        "user": _user_payload(user),
    }


def _user_payload(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "email_verified": True,
        "is_active": bool(user.is_active),
        "subscription_status": user.subscription_status or "basic",
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


def _validate_password(password: str, password_confirm: Optional[str] = None) -> None:
    if len(password) < 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 8 characters")
    if password_confirm is not None and password != password_confirm:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Passwords do not match")


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    password_confirm: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


@router.post("/register", status_code=status.HTTP_201_CREATED)
@rate_limit("20/hour")
async def register(
    request: Request,
    payload: RegisterRequest,
    response: Response,
    db: Session = Depends(get_db),
):
    normalized_email = str(payload.email).strip().lower()
    _validate_password(payload.password, payload.password_confirm)

    user = User(
        email=normalized_email,
        hashed_password=hash_password(payload.password),
        created_at=datetime.utcnow(),
        is_active=True,
        subscription_status="basic",
        email_verified=True,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        existing = db.query(User).filter(func.lower(User.email) == normalized_email).first()
        if existing:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered") from exc
        raise
    db.refresh(user)
    return _token_response(user, response)


@router.post("/login")
@rate_limit("30/hour")
async def login(
    request: Request,
    payload: LoginRequest,
    response: Response,
    db: Session = Depends(get_db),
):
    normalized_email = str(payload.email).strip().lower()
    user = db.query(User).filter(func.lower(User.email) == normalized_email).first()
    if user is None or not user.is_active or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    user.email_verified = True
    user.last_login = datetime.utcnow()
    user.last_login_ip = request.client.host if request.client else None
    db.commit()
    db.refresh(user)
    return _token_response(user, response)


@router.get("/me")
async def me(current_user: User = Depends(get_current_user)):
    return _user_payload(current_user)


@router.post("/logout")
async def logout(
    response: Response,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    current_user.auth_token_version = int(current_user.auth_token_version or 0) + 1
    db.commit()
    _clear_auth_cookies(response)
    return {"message": "Logged out"}
