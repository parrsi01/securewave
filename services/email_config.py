"""Shared parsing helpers for the transactional email services."""

import os
from typing import Optional, Tuple


DEFAULT_SMTP_PORT = 587


def configured_env(name: str, default: Optional[str] = None) -> Optional[str]:
    """Read an environment value while ignoring empty/template values."""
    value = os.getenv(name)
    if value is None:
        return default
    value = value.strip()
    if not value or (value.startswith("<") and value.endswith(">")):
        return None
    return value


def parse_smtp_port(raw_value: Optional[str]) -> Tuple[int, bool]:
    """Return a safe SMTP port and whether the supplied value is valid."""
    if raw_value is None:
        return DEFAULT_SMTP_PORT, False
    try:
        port = int(raw_value)
    except ValueError:
        return DEFAULT_SMTP_PORT, False
    return port, 1 <= port <= 65535
