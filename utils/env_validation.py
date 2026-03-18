"""
Environment validation helpers for SecureWave.
"""

from __future__ import annotations

import os
from typing import List, Optional, Tuple

from cryptography.fernet import Fernet

from config.settings import collect_configuration_errors


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


def check_encryption_key_at_startup(env_var_name: str = "WG_ENCRYPTION_KEY") -> None:
    """
    Raise RuntimeError if the named Fernet encryption key is absent or invalid.

    Call this during service startup to fail fast before any key material is
    processed.  Raises RuntimeError with the env_var_name in the message so
    that log scanners can identify which key is missing.
    """
    value = os.getenv(env_var_name, "").strip()
    issue = validate_fernet_key(value if value else None)
    if issue:
        raise RuntimeError(
            f"{env_var_name} is {issue}. "
            "A valid Fernet key is required for private key encryption."
        )


def _bool_from_env(value: Optional[str]) -> Optional[bool]:
    if value is None:
        return None
    return value.strip().lower() in ("1", "true", "yes", "on")


def is_testing() -> bool:
    return os.getenv("TESTING", "").strip().lower() == "true"


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
    else:
        missing.append(f"EMAIL_PROVIDER({resolved})")

    return resolved, missing


def stripe_config_issues() -> List[str]:
    """Return missing Stripe variables for hosted checkout in production."""
    missing: List[str] = []

    def require(name: str) -> None:
        if not os.getenv(name):
            missing.append(name)

    require("STRIPE_SECRET_KEY")
    require("STRIPE_PUBLISHABLE_KEY")
    require("STRIPE_WEBHOOK_SECRET")
    require("STRIPE_PRICE_BASIC_MONTHLY")
    require("STRIPE_PRICE_PREMIUM_MONTHLY")
    require("STRIPE_PRICE_ULTRA_MONTHLY")
    return missing


def production_env_errors() -> List[str]:
    """Collect hard errors for production mode."""
    if not is_production():
        return []

    environ = dict(os.environ)

    # Treat JWT_SECRET as the canonical root secret for validation snapshots so
    # inherited alias variables from the parent shell do not create false
    # positives when the current target configuration intentionally relies on
    # derived access/refresh secrets.
    if (environ.get("JWT_SECRET") or "").strip():
        environ.pop("ACCESS_TOKEN_SECRET", None)
        environ.pop("REFRESH_TOKEN_SECRET", None)

    errors: List[str] = collect_configuration_errors(environ)

    provider, missing = email_config_issues()
    if missing:
        errors.append(f"EMAIL_PROVIDER({provider}) missing: {', '.join(missing)}")

    for key_name in ("PAYMENTS_MOCK", "DEMO_MODE", "WG_MOCK_MODE"):
        if _bool_from_env(os.getenv(key_name)):
            errors.append(f"{key_name} must not be true in production")

    stripe_missing = stripe_config_issues()
    if stripe_missing:
        errors.append(f"Stripe missing: {', '.join(stripe_missing)}")

    return list(dict.fromkeys(errors))
