"""The single SecureWave Beta authentication path.

Beta accounts are deliberately small: normalized email, password hash, and a
token generation counter used to invalidate sessions on logout. Email
delivery, verification, payments, and account gates are outside this path.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.hashing_service import hash_password, verify_password
from services.jwt_service import create_access_token, get_current_user
from utils.password_policy import validate_password_strength

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auth", tags=["auth"])


class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=72)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


def _normalize_email(raw: str) -> str:
    email = raw.strip().lower()
    if (
        len(email) > 254
        or "@" not in email
        or email.startswith("@")
        or email.endswith("@")
        or any(char.isspace() for char in email)
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Enter a valid email address.",
        )
    local, domain = email.rsplit("@", 1)
    if not local or "." not in domain or domain.startswith(".") or domain.endswith("."):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Enter a valid email address.",
        )
    return email


def _issue_token(user: User) -> TokenResponse:
    return TokenResponse(access_token=create_access_token(user))


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(payload: Credentials, db: Session = Depends(get_db)) -> TokenResponse:
    email = _normalize_email(payload.email)
    password_error = validate_password_strength(payload.password)
    if password_error:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=password_error)

    if db.query(User).filter(func.lower(User.email) == email).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered.")

    user = User(
        email=email,
        hashed_password=hash_password(payload.password),
        created_at=datetime.utcnow(),
        is_active=True,
        auth_token_version=0,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        logger.info("Registration rejected after unique constraint")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered.") from exc
    db.refresh(user)
    logger.info("User registered user_id=%s", user.id)
    return _issue_token(user)


@router.post("/login", response_model=TokenResponse)
def login(payload: Credentials, db: Session = Depends(get_db)) -> TokenResponse:
    email = _normalize_email(payload.email)
    user = db.query(User).filter(func.lower(User.email) == email).first()
    if user is None or not user.is_active or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    logger.info("User login succeeded user_id=%s", user.id)
    return _issue_token(user)


@router.get("/me")
def me(current_user: User = Depends(get_current_user)) -> dict[str, object]:
    return {
        "id": current_user.id,
        "email": current_user.email,
        "is_active": bool(current_user.is_active),
    }


@router.post("/logout")
def logout(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict[str, str]:
    current_user.auth_token_version = int(current_user.auth_token_version or 0) + 1
    db.commit()
    return {"message": "Logged out."}
