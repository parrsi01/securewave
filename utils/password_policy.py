import re
from typing import Optional

# L-1: bcrypt 72-byte truncation is NOT a risk for new passwords.
# The primary hasher is Argon2id (no 72-byte limit).  bcrypt is only used as a
# legacy verify path for existing hashes and truncates the *input to verify*
# at 72 bytes (hashing_service.py: verify_password[:_BCRYPT_MAX_BYTES]).
# New passwords are hashed with Argon2id exclusively.
# The 1000-byte hard cap in hashing_service._validate_input() prevents DoS on all paths.


def validate_password_strength(password: str) -> Optional[str]:
    if len(password) < 10:
        return "Password must be at least 10 characters long"
    if not re.search(r"[a-z]", password):
        return "Password must include at least one lowercase letter"
    if not re.search(r"[A-Z]", password):
        return "Password must include at least one uppercase letter"
    if not re.search(r"\d", password):
        return "Password must include at least one number"
    if not re.search(r"[!@#$%^&*()_+\-=\[\]{};':\"\\|,.<>/?`~]", password):
        return "Password must include at least one special character"
    return None
