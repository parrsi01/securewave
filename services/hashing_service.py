import os

try:
    from passlib.context import CryptContext
    _HAS_PASSLIB = True
except ImportError:
    CryptContext = None
    _HAS_PASSLIB = False
    import crypt

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


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=_bcrypt_rounds()) if _HAS_PASSLIB else None

if not _HAS_PASSLIB:
    _CRYPT_BCRYPT = getattr(crypt, "METHOD_BLOWFISH", None)
    _CRYPT_FALLBACK = crypt.METHOD_SHA512

def _crypt_hash(password: str) -> str:
    method = _CRYPT_BCRYPT or _CRYPT_FALLBACK
    return crypt.crypt(password, crypt.mksalt(method))

def _crypt_verify(plain_password: str, hashed_password: str) -> bool:
    return crypt.crypt(plain_password, hashed_password) == hashed_password


def hash_password(password: str) -> str:
    """Hash a password using bcrypt"""
    # Limit password length to 72 characters (bcrypt limit)
    if len(password) > 72:
        password = password[:72]
    if pwd_context:
        return pwd_context.hash(password)
    return _crypt_hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its bcrypt hash"""
    # Limit password length to 72 characters (bcrypt limit)
    if len(plain_password) > 72:
        plain_password = plain_password[:72]
    if pwd_context:
        return pwd_context.verify(plain_password, hashed_password)
    return _crypt_verify(plain_password, hashed_password)
