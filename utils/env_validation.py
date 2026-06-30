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
    """Demo mode defaults to true for non-release environments."""
    env_value = _bool_from_env(os.getenv("DEMO_MODE"))
    if env_value is not None:
        return env_value
    return get_environment() not in ("production", "staging")


def wg_mock_mode_enabled() -> bool:
    """WireGuard mock mode defaults to true for non-release environments."""
    env_value = _bool_from_env(os.getenv("WG_MOCK_MODE"))
    if env_value is not None:
        return env_value
    return get_environment() not in ("production", "staging")


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
    app_url = os.getenv("APP_URL") or os.getenv("APP_BASE_URL")

    if resolved == "smtp":
        require("SMTP_HOST", os.getenv("SMTP_HOST"))
        smtp_port = os.getenv("SMTP_PORT")
        require("SMTP_PORT", smtp_port)
        if smtp_port:
            try:
                int(smtp_port)
            except ValueError:
                missing.append("SMTP_PORT(valid integer)")
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
    require("APP_URL", app_url)

    return resolved, missing


def payment_config_issues(provider: Optional[str] = None) -> Tuple[str, List[str]]:
    """Return payment provider name and list of missing release config variables."""
    resolved = (provider or os.getenv("PAYMENT_PROVIDER") or "stripe").strip().lower()
    missing: List[str] = []

    def require(name: str, value: Optional[str]) -> None:
        if not value:
            missing.append(name)

    if os.getenv("PAYMENTS_MOCK", "false").strip().lower() == "true":
        missing.append("PAYMENTS_MOCK(false)")
    if os.getenv("DEMO_BILLING", "false").strip().lower() == "true":
        missing.append("DEMO_BILLING(false)")

    if resolved == "stripe":
        stripe_secret = os.getenv("STRIPE_SECRET_KEY") or os.getenv("STRIPE_SECRET")
        require("STRIPE_SECRET_KEY", stripe_secret)
        require("STRIPE_WEBHOOK_SECRET", os.getenv("STRIPE_WEBHOOK_SECRET"))
        require("STRIPE_PUBLISHABLE_KEY", os.getenv("STRIPE_PUBLISHABLE_KEY"))
        require("STRIPE_PORTAL_CONFIG_ID", os.getenv("STRIPE_PORTAL_CONFIG_ID"))

        if stripe_secret and not (
            stripe_secret.startswith("sk_live_") or stripe_secret.startswith("rk_live_")
        ):
            missing.append("STRIPE_SECRET_KEY(live)")
        webhook_secret = os.getenv("STRIPE_WEBHOOK_SECRET")
        if webhook_secret and not webhook_secret.startswith("whsec_"):
            missing.append("STRIPE_WEBHOOK_SECRET(whsec)")
        publishable_key = os.getenv("STRIPE_PUBLISHABLE_KEY")
        if publishable_key and not publishable_key.startswith("pk_live_"):
            missing.append("STRIPE_PUBLISHABLE_KEY(live)")
        portal_config_id = os.getenv("STRIPE_PORTAL_CONFIG_ID")
        if portal_config_id and not portal_config_id.startswith("bpc_"):
            missing.append("STRIPE_PORTAL_CONFIG_ID(bpc_)")

        for plan in ("BASIC", "PREMIUM", "ULTRA"):
            for cycle in ("MONTHLY", "YEARLY"):
                price_key = f"STRIPE_PRICE_{plan}_{cycle}"
                price_id = os.getenv(price_key)
                require(price_key, price_id)
                if price_id and not price_id.startswith("price_"):
                    missing.append(f"{price_key}(price_)")
    elif resolved == "paypal":
        require("PAYPAL_CLIENT_ID", os.getenv("PAYPAL_CLIENT_ID"))
        require("PAYPAL_CLIENT_SECRET", os.getenv("PAYPAL_CLIENT_SECRET"))
        if os.getenv("PAYPAL_MODE", "").strip().lower() != "live":
            missing.append("PAYPAL_MODE(live)")
    else:
        missing.append(f"PAYMENT_PROVIDER({resolved})")

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

    payment_provider, payment_missing = payment_config_issues()
    if payment_missing:
        errors.append(f"PAYMENT_PROVIDER({payment_provider}) missing: {', '.join(payment_missing)}")

    for flag in ("DEMO_MODE", "WG_MOCK_MODE"):
        value = os.getenv(flag)
        if value is None:
            errors.append(f"{flag} must be set to false in production")
        elif value.strip().lower() != "false":
            errors.append(f"{flag} must be false in production (got {value})")

    return errors
