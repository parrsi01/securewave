from __future__ import annotations

from models.user import User
from services.jwt_service import create_access_token


def access_token_for_user(user: User) -> str:
    return create_access_token(user)


def auth_headers_for_user(user: User) -> dict[str, str]:
    token = access_token_for_user(user)
    return {"Authorization": f"Bearer {token}"}

