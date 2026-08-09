"""Minimal environment helpers for the Linux beta runtime."""

from __future__ import annotations

import os
from typing import Optional

from cryptography.fernet import Fernet
from dotenv import load_dotenv


def load_environment_dotenv() -> None:
    load_dotenv()
    environment = get_environment()
    if environment == "production":
        load_dotenv(".env.production")
    elif environment == "staging":
        load_dotenv(".env.staging")


def get_environment() -> str:
    return os.getenv("ENVIRONMENT", "development").strip().lower()


def is_production() -> bool:
    return get_environment() == "production"


def validate_fernet_key(value: Optional[str]) -> Optional[str]:
    if not value:
        return "missing"
    try:
        Fernet(value.encode())
    except Exception:
        return "invalid"
    return None
