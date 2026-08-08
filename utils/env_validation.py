"""
Environment validation helpers for SecureWave.
"""

from __future__ import annotations

import os
from typing import List, Optional, Tuple

from cryptography.fernet import Fernet


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


def _bool_from_env(value: Optional[str]) -> Optional[bool]:
    if value is None:
        return None
    return value.strip().lower() in ("1", "true", "yes", "on")


def demo_mode_enabled() -> bool:
    """Return explicit demo mode; live behavior is the safe default."""
    env_value = _bool_from_env(os.getenv("DEMO_MODE"))
    if env_value is not None:
        return env_value
    return False


def wg_mock_mode_enabled() -> bool:
    """Return explicit WireGuard mock mode; real mode is the safe default."""
    env_value = _bool_from_env(os.getenv("WG_MOCK_MODE"))
    if env_value is not None:
        return env_value
    return False


def email_config_issues(provider: Optional[str] = None) -> Tuple[str, List[str]]:
    """Return provider name and list of missing email config variables."""
    resolved = (provider or os.getenv("EMAIL_PROVIDER") or "smtp").strip().lower()
    missing: List[str] = []

    def require(name: str, value: Optional[str]) -> None:
        if not value:
            missing.append(name)

    from_email = (
        os.getenv("FROM_EMAIL")
        or os.getenv("SMTP_FROM_EMAIL")
        or os.getenv("SMTP_USER")
    )

    if resolved == "smtp":
        require("SMTP_HOST", os.getenv("SMTP_HOST"))
        require("SMTP_PORT", os.getenv("SMTP_PORT"))
        require("SMTP_USER", os.getenv("SMTP_USER"))
        require("SMTP_PASSWORD", os.getenv("SMTP_PASSWORD"))
        require("FROM_EMAIL", from_email)
    elif resolved == "sendgrid":
        require("SENDGRID_API_KEY", os.getenv("SENDGRID_API_KEY"))
        require("FROM_EMAIL", from_email)
    elif resolved in ("ses", "aws_ses"):
        require("FROM_EMAIL", from_email)
        require("AWS_SES_REGION", os.getenv("AWS_SES_REGION"))
    elif resolved == "local_capture":
        if get_environment() != "codex-local":
            missing.append("EMAIL_PROVIDER(local_capture) requires ENVIRONMENT=codex-local")
        require(
            "SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR",
            os.getenv("SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR"),
        )
    else:
        missing.append(f"EMAIL_PROVIDER({resolved})")

    return resolved, missing


def production_env_errors() -> List[str]:
    """Collect hard errors for production mode."""
    if not is_production():
        return []

    errors: List[str] = []

    for key_name in ("AUTH_ENCRYPTION_KEY", "WG_ENCRYPTION_KEY"):
        issue = validate_fernet_key(os.getenv(key_name))
        if issue:
            errors.append(f"{key_name} {issue}")

    provider, missing = email_config_issues()
    if missing:
        errors.append(f"EMAIL_PROVIDER({provider}) missing: {', '.join(missing)}")

    for flag in ("DEMO_MODE", "WG_MOCK_MODE"):
        value = os.getenv(flag)
        if value is None:
            errors.append(f"{flag} must be set to false in production")
        elif value.strip().lower() != "false":
            errors.append(f"{flag} must be false in production (got {value})")

    return errors
