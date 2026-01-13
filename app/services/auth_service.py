from typing import Optional
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.core import security, config
from app.models.user import User
from app.models.audit_log import AuditLog


def get_user_by_email(db: Session, email: str) -> Optional[User]:
    return db.query(User).filter(User.email == email).first()


def get_user_by_id(db: Session, user_id: int) -> Optional[User]:
    return db.query(User).filter(User.id == user_id).first()


def register_user(db: Session, email: str, password: str) -> User:
    user = User(email=email, hashed_password=security.hash_password(password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def authenticate_user(db: Session, email: str, password: str) -> Optional[User]:
    user = get_user_by_email(db, email)
    if not user:
        return None
    if user.locked_until and user.locked_until > datetime.utcnow():
        return None
    if not security.verify_password(password, user.hashed_password):
        return None
    return user


def issue_tokens(user: User) -> dict:
    access = security.create_access_token(str(user.id))
    refresh = security.create_refresh_token(str(user.id))
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer"}


def record_login_attempt(db: Session, user: Optional[User], email: str, ip_address: Optional[str], success: bool) -> None:
    entry = AuditLog(
        user_id=user.id if user else None,
        action="login_success" if success else "login_failed",
        email=email,
        ip_address=ip_address,
    )
    db.add(entry)

    if user:
        if success:
            user.failed_login_attempts = 0
            user.locked_until = None
            user.last_login_at = datetime.utcnow()
        else:
            user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
            if user.failed_login_attempts >= config.MAX_FAILED_LOGIN_ATTEMPTS:
                user.locked_until = datetime.utcnow() + timedelta(minutes=config.LOCKOUT_MINUTES)
    db.commit()


def update_refresh_token_hash(db: Session, user: User, refresh_token: str) -> None:
    user.refresh_token_hash = security.hash_token(refresh_token)
    db.commit()
