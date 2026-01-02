from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from models.user import User
from services.hashing_service import hash_password, verify_password
from services.jwt_service import create_access_token, create_refresh_token, verify_refresh_token, get_current_user
from database.session import get_db

router = APIRouter()


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


@router.post("/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        created_at=datetime.utcnow(),
        subscription_status="inactive",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
    )


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user: Optional[User] = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    token_data = verify_refresh_token(payload.refresh_token)
    user = db.query(User).filter(User.id == int(token_data.get("sub"))).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
    )


# TODO: Implement email-based password reset with verification
# The previous reset-password endpoint was removed due to security vulnerability
# (allowed anyone to reset any user's password without verification)
# Future implementation should:
# 1. Generate secure one-time token
# 2. Send token to user's email
# 3. Verify token before allowing password change
# 4. Expire tokens after 15 minutes


@router.get("/users/me")
def get_current_user_info(current_user: User = Depends(get_current_user)):
    """Get current user information"""
    return {
        "id": current_user.id,
        "email": current_user.email,
        "created_at": current_user.created_at.isoformat() if current_user.created_at else None,
        "subscription_active": current_user.subscription_status == "active",
        "subscription_status": current_user.subscription_status
    }
