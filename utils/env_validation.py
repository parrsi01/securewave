"""
Environment validation helpers for SecureWave.
"""

from __future__ import annotations

import os
from typing import Optional

from cryptography.fernet import Fernet
from dotenv import load_dotenv


def load_environment_dotenv() -> None:
    """Load only the dotenv file for the selected environment.

    The process environment still wins because dotenv's default is
    non-overriding.
    """
    load_dotenv()
    environment = get_environment()
    if environment == "production":
        load_dotenv(".env.production")


def get_environment() -> str:
    return os.getenv("ENVIRONMENT", "development").strip().lower()


def is_production() -> bool:
    return get_environment() == "production"


def validate_fernet_key(value: Optional[str]) -> Optional[str]:
    """Return an error string if the Fernet key is missing/invalid."""
    if not value:
        return "missing"
    try:
        Fernet(value.encode())
    except Exception as exc:  # pragma: no cover - error detail for logs/scripts
        return f"invalid ({exc})"
    return None
