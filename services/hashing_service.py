import os

from passlib.context import CryptContext

def _bcrypt_rounds() -> int:
    env_rounds = os.getenv("BCRYPT_ROUNDS")
    if env_rounds:
        try:
            return max(4, int(env_rounds))
        except ValueError:
            return 12
    if os.getenv("TESTING", "").lower() == "true":
        return 4
    return 12


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=_bcrypt_rounds())


def hash_password(password: str) -> str:
    """Hash a password using bcrypt"""
    # Limit password length to 72 characters (bcrypt limit)
    if len(password) > 72:
        password = password[:72]
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its bcrypt hash"""
    # Limit password length to 72 characters (bcrypt limit)
    if len(plain_password) > 72:
        plain_password = plain_password[:72]
    return pwd_context.verify(plain_password, hashed_password)
