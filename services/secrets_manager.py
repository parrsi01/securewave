"""
SecureWave VPN - Secrets Management Service
Uses environment variables for secret storage.
"""

import os
import logging
from typing import Optional, Dict
from dotenv import load_dotenv

load_dotenv()
load_dotenv(".env.production")

logger = logging.getLogger(__name__)


class SecretsManager:
    """
    Unified secrets management service.
    Environment variables are the only supported provider.
    """

    def __init__(self):
        self.use_env = True

    def get_secret(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """
        Get secret from environment variables.

        Args:
            secret_name: Name of the secret (e.g., "DATABASE_URL", "STRIPE_SECRET_KEY")
            default: Default value if secret not found

        Returns:
            Secret value or default
        """
        try:
            return self._get_from_env(secret_name, default)
        except Exception as e:
            logger.error("Error retrieving secret %s: %s", secret_name, e)
            return default

    def _get_from_env(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """Retrieve secret from environment variables."""
        value = os.getenv(secret_name, None)
        if value is None:
            value = os.getenv(secret_name.replace("-", "_"), default)
        if value:
            logger.debug("✓ Retrieved secret from environment: %s", secret_name)
        return value

    def set_secret(self, secret_name: str, secret_value: str) -> bool:
        """
        Setting secrets at runtime is not supported.
        """
        logger.warning("Secrets manager is read-only. Set %s via environment variables.", secret_name)
        return False

    def delete_secret(self, secret_name: str) -> bool:
        """
        Deleting secrets at runtime is not supported.
        """
        logger.warning("Secrets manager is read-only. Remove %s from the environment instead.", secret_name)
        return False

    def get_all_secrets(self) -> Dict[str, str]:
        """
        Get all application secrets (for migration/backup purposes).

        Returns:
            Dictionary of secret names to masked values
        """
        secrets = {}
        secret_names = [
            "DATABASE_URL",
            "POSTGRES_PASSWORD",
            "SECRET_KEY",
            "JWT_SECRET_KEY",
            "STRIPE_SECRET_KEY",
            "STRIPE_WEBHOOK_SECRET",
            "STRIPE_PUBLISHABLE_KEY",
            "PAYPAL_CLIENT_ID",
            "PAYPAL_CLIENT_SECRET",
            "PAYPAL_WEBHOOK_ID",
            "SMTP_HOST",
            "SMTP_PORT",
            "SMTP_USER",
            "SMTP_PASSWORD",
            "WIREGUARD_PRIVATE_KEY",
            "REDIS_URL",
        ]

        for secret_name in secret_names:
            value = self.get_secret(secret_name)
            if value:
                secrets[secret_name] = "***" if len(value) < 100 else f"***({len(value)} chars)"

        return secrets

    def health_check(self) -> Dict[str, any]:
        """Check secrets manager health."""
        return {
            "status": "healthy",
            "provider": "environment_variables",
            "connected": True,
        }


_secrets_manager = None


def get_secrets_manager() -> SecretsManager:
    """Get singleton secrets manager instance."""
    global _secrets_manager
    if _secrets_manager is None:
        _secrets_manager = SecretsManager()
    return _secrets_manager


def get_secret(secret_name: str, default: Optional[str] = None) -> Optional[str]:
    """Convenience function to get a secret."""
    return get_secrets_manager().get_secret(secret_name, default)
