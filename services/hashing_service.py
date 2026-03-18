"""
Password hashing service — Argon2id primary, bcrypt fallback for legacy hashes.

Security properties:
- Argon2id (OWASP recommended): time_cost=3, memory_cost=65536, parallelism=2
- Reduced params in test mode for speed: time_cost=1, memory_cost=8192, parallelism=1
- bcrypt: still accepted for verify() on existing hashes; flagged for rehash
- Input capped at 1000 bytes to prevent DoS; bcrypt path capped at 72 bytes
- passwords over 1000 bytes raise ValueError — callers must validate upstream
"""

import os

from config.settings import get_settings

# ---------------------------------------------------------------------------
# Argon2id
# ---------------------------------------------------------------------------
try:
    from argon2 import PasswordHasher
    from argon2.exceptions import VerifyMismatchError, VerificationError, InvalidHashError

    _HAS_ARGON2 = True
except ImportError:
    _HAS_ARGON2 = False

# ---------------------------------------------------------------------------
# bcrypt (via passlib)
# ---------------------------------------------------------------------------
try:
    from passlib.context import CryptContext
    _HAS_PASSLIB = True
except ImportError:
    CryptContext = None
    _HAS_PASSLIB = False

SETTINGS = get_settings()

_MAX_INPUT_BYTES = 1000
_BCRYPT_MAX_BYTES = 72


def _is_testing() -> bool:
    return SETTINGS.testing or os.getenv("TESTING", "").strip().lower() == "true"


def _make_argon2_hasher() -> "PasswordHasher":
    if _is_testing():
        return PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)
    return PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)


def _bcrypt_rounds() -> int:
    env_rounds = os.getenv("BCRYPT_ROUNDS")
    if env_rounds:
        try:
            return max(4, int(env_rounds))
        except ValueError:
            return 12
    return 4 if _is_testing() else 12


_bcrypt_ctx = (
    CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=_bcrypt_rounds())
    if _HAS_PASSLIB
    else None
)


def _validate_input(password: str) -> None:
    if len(password.encode("utf-8")) > _MAX_INPUT_BYTES:
        raise ValueError(
            f"Password exceeds maximum allowed length of {_MAX_INPUT_BYTES} bytes"
        )


def hash_password(password: str) -> str:
    """Hash a password.  Uses Argon2id when available, bcrypt otherwise."""
    _validate_input(password)
    if _HAS_ARGON2:
        return _make_argon2_hasher().hash(password)
    if _bcrypt_ctx:
        return _bcrypt_ctx.hash(password[:_BCRYPT_MAX_BYTES])
    raise RuntimeError("No password hashing library available (argon2-cffi or passlib required)")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify plain against hash.  Auto-detects Argon2 vs bcrypt."""
    if not plain_password or not hashed_password:
        return False
    # Argon2 hashes start with $argon2
    if hashed_password.startswith("$argon2"):
        if not _HAS_ARGON2:
            return False
        try:
            return _make_argon2_hasher().verify(hashed_password, plain_password)
        except (VerifyMismatchError, VerificationError, InvalidHashError):
            return False
    # bcrypt hashes start with $2b$ or $2a$
    if _bcrypt_ctx:
        try:
            return _bcrypt_ctx.verify(plain_password[:_BCRYPT_MAX_BYTES], hashed_password)
        except Exception:
            return False
    return False


def needs_rehash(hashed_password: str) -> bool:
    """Return True if the hash should be upgraded (bcrypt → Argon2id, or stale Argon2 params)."""
    if not hashed_password:
        return False
    if hashed_password.startswith("$argon2"):
        if not _HAS_ARGON2:
            return False
        try:
            return _make_argon2_hasher().check_needs_rehash(hashed_password)
        except Exception:
            return True
    # bcrypt hash always needs rehash when Argon2 is available
    return _HAS_ARGON2
