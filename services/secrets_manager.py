"""
SecureWave VPN - Secrets Management Service
Handles read-only secret retrieval from process environment.
"""

import os
import logging
from typing import Any, Optional, Dict
from utils.env_validation import load_environment_dotenv

load_environment_dotenv()

logger = logging.getLogger(__name__)


class SecretsManager:
    """
    Unified read-only secrets management service.

    Deployment platforms inject secrets through environment variables or an
    external secret manager before process startup. This class intentionally
    does not talk to a cloud-provider API.
    """

    def __init__(self):
        """Initialize secrets manager"""
        self.provider = "environment_variables"

    def get_secret(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """
        Get secret from environment variables.

        Args:
            secret_name: Name of the secret (e.g., "DATABASE-URL", "STRIPE-SECRET-KEY")
            default: Default value if secret not found

        Returns:
            Secret value or default
        """
        try:
            return self._get_from_env(secret_name, default)

        except Exception as e:
            logger.error(f"Error retrieving secret {secret_name}: {e}")
            return default

    def _get_from_env(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """
        Retrieve secret from environment variables

        Args:
            secret_name: Name of environment variable
            default: Default value

        Returns:
            Environment variable value or default
        """
        value = os.getenv(secret_name, None)

        if value is None:
            value = os.getenv(secret_name.replace("-", "_"), default)

        if value:
            logger.debug(f"✓ Retrieved secret from environment: {secret_name}")

        return value

    def set_secret(self, secret_name: str, secret_value: str) -> bool:
        """
        Reject runtime secret mutation.

        Args:
            secret_name: Name of the secret
            secret_value: Secret value

        Returns:
            True if successful
        """
        logger.warning("Secret mutation is not supported at runtime: %s", secret_name)
        return False

    def delete_secret(self, secret_name: str) -> bool:
        """
        Reject runtime secret deletion.

        Args:
            secret_name: Name of the secret

        Returns:
            True if successful
        """
        logger.warning("Secret deletion is not supported at runtime: %s", secret_name)
        return False

    def get_all_secrets(self) -> Dict[str, str]:
        """
        Get all application secrets (for migration/backup purposes)

        Returns:
            Dictionary of secret names to values
        """
        secrets = {}

        # List of all secrets used by the application
        secret_names = [
            # Database
            "DATABASE_URL",
            "POSTGRES_PASSWORD",

            # JWT & Auth
            "SECRET_KEY",
            "JWT_SECRET_KEY",

            # Payment providers
            "STRIPE_SECRET_KEY",
            "STRIPE_WEBHOOK_SECRET",
            "STRIPE_PUBLISHABLE_KEY",
            "PAYPAL_CLIENT_ID",
            "PAYPAL_CLIENT_SECRET",
            "PAYPAL_WEBHOOK_ID",

            # Email/SMTP
            "SMTP_HOST",
            "SMTP_PORT",
            "SMTP_USER",
            "SMTP_PASSWORD",

            # VPN
            "WIREGUARD_PRIVATE_KEY",

            # Other
            "REDIS_URL",
        ]

        for secret_name in secret_names:
            value = self.get_secret(secret_name)
            if value:
                # Don't include full secret values in logs
                secrets[secret_name] = "***" if len(value) < 100 else f"***({len(value)} chars)"

        return secrets

    def health_check(self) -> Dict[str, Any]:
        """
        Check secrets manager health

        Returns:
            Health status dictionary
        """
        return {
            "status": "healthy",
            "provider": self.provider,
            "connected": True,
        }


# Singleton instance
_secrets_manager = None


def get_secrets_manager() -> SecretsManager:
    """Get singleton secrets manager instance"""
    global _secrets_manager
    if _secrets_manager is None:
        _secrets_manager = SecretsManager()
    return _secrets_manager


# Convenience function for getting secrets
def get_secret(secret_name: str, default: Optional[str] = None) -> Optional[str]:
    """
    Convenience function to get a secret

    Args:
        secret_name: Name of the secret
        default: Default value

    Returns:
        Secret value or default
    """
    return get_secrets_manager().get_secret(secret_name, default)
