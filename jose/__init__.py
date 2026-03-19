from jwt import InvalidTokenError as JWTError

from . import jwt

__all__ = ["JWTError", "jwt"]
