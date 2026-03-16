import re
from typing import Optional


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
