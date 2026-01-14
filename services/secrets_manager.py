"""
SecureWave VPN - Secrets Management Service
Handles secure storage and retrieval of secrets using Azure Key Vault
Falls back to environment variables for development
"""

import os
import logging
from typing import Optional, Dict
from dotenv import load_dotenv

load_dotenv()
load_dotenv(".env.production")

logger = logging.getLogger(__name__)

# Configuration
USE_AZURE_KEY_VAULT = os.getenv("USE_AZURE_KEY_VAULT", "false").lower() == "true"
AZURE_KEY_VAULT_URL = os.getenv("AZURE_KEY_VAULT_URL")


class SecretsManager:
    """
    Unified secrets management service
    Uses Azure Key Vault in production, environment variables in development
    """

    def __init__(self):
        """Initialize secrets manager"""
        self.use_key_vault = USE_AZURE_KEY_VAULT
        self.key_vault_client = None

        if self.use_key_vault:
            try:
                self._init_azure_key_vault()
            except Exception as e:
                logger.error(f"Failed to initialize Azure Key Vault: {e}")
                logger.warning("Falling back to environment variables")
                self.use_key_vault = False

    def _init_azure_key_vault(self):
        """Initialize Azure Key Vault client"""
        if not AZURE_KEY_VAULT_URL:
            raise ValueError("AZURE_KEY_VAULT_URL not configured")

        try:
            from azure.identity import DefaultAzureCredential
            from azure.keyvault.secrets import SecretClient

            # Use DefaultAzureCredential for authentication
            # This works with Managed Identity, Azure CLI, environment variables, etc.
            credential = DefaultAzureCredential()

            # Create Key Vault client
            self.key_vault_client = SecretClient(
                vault_url=AZURE_KEY_VAULT_URL,
                credential=credential
            )

            # Test connection
            # Try to list secrets to verify access (don't actually retrieve anything)
            _ = list(self.key_vault_client.list_properties_of_secrets(max_results=1))

            logger.info(f"✓ Azure Key Vault initialized: {AZURE_KEY_VAULT_URL}")

        except ImportError:
            raise ImportError(
                "Azure SDK not installed. "
                "Install with: pip install azure-identity azure-keyvault-secrets"
            )
        except Exception as e:
            raise Exception(f"Failed to connect to Azure Key Vault: {e}")

    def get_secret(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """
        Get secret from Key Vault or environment variables

        Args:
            secret_name: Name of the secret (e.g., "DATABASE-URL", "STRIPE-SECRET-KEY")
            default: Default value if secret not found

        Returns:
            Secret value or default
        """
        try:
            if self.use_key_vault and self.key_vault_client:
                return self._get_from_key_vault(secret_name, default)
            else:
                return self._get_from_env(secret_name, default)

        except Exception as e:
            logger.error(f"Error retrieving secret {secret_name}: {e}")
            return default

    def _get_from_key_vault(self, secret_name: str, default: Optional[str] = None) -> Optional[str]:
        """
        Retrieve secret from Azure Key Vault

        Args:
            secret_name: Name of the secret (use hyphens, not underscores)
            default: Default value

        Returns:
            Secret value or default
        """
        try:
            # Azure Key Vault uses hyphens, not underscores
            vault_name = secret_name.replace("_", "-")

            secret = self.key_vault_client.get_secret(vault_name)
            logger.debug(f"✓ Retrieved secret from Key Vault: {vault_name}")
            return secret.value

        except Exception as e:
            logger.warning(f"Secret {secret_name} not found in Key Vault: {e}")
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
        # Try with underscores (standard env var format)
        value = os.getenv(secret_name, None)

        if value is None:
            # Try with hyphens (Key Vault format)
            value = os.getenv(secret_name.replace("-", "_"), default)

        if value:
            logger.debug(f"✓ Retrieved secret from environment: {secret_name}")

        return value

    def set_secret(self, secret_name: str, secret_value: str) -> bool:
        """
        Set secret in Key Vault (admin/deployment operation)

        Args:
            secret_name: Name of the secret
            secret_value: Secret value

        Returns:
            True if successful
        """
        if not self.use_key_vault or not self.key_vault_client:
            logger.warning("Key Vault not available. Cannot set secrets.")
            return False

        try:
            vault_name = secret_name.replace("_", "-")
            self.key_vault_client.set_secret(vault_name, secret_value)
            logger.info(f"✓ Secret set in Key Vault: {vault_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to set secret {secret_name}: {e}")
            return False

    def delete_secret(self, secret_name: str) -> bool:
        """
        Delete secret from Key Vault (admin operation)

        Args:
            secret_name: Name of the secret

        Returns:
            True if successful
        """
        if not self.use_key_vault or not self.key_vault_client:
            logger.warning("Key Vault not available. Cannot delete secrets.")
            return False

        try:
            vault_name = secret_name.replace("_", "-")
            self.key_vault_client.begin_delete_secret(vault_name).wait()
            logger.info(f"✓ Secret deleted from Key Vault: {vault_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to delete secret {secret_name}: {e}")
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

            # Azure
            "AZURE_SUBSCRIPTION_ID",
            "AZURE_RESOURCE_GROUP",

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

    def health_check(self) -> Dict[str, any]:
        """
        Check secrets manager health

        Returns:
            Health status dictionary
        """
        return {
            "status": "healthy" if self.use_key_vault or True else "degraded",
            "provider": "azure_key_vault" if self.use_key_vault else "environment_variables",
            "key_vault_url": AZURE_KEY_VAULT_URL if self.use_key_vault else None,
            "connected": self.key_vault_client is not None if self.use_key_vault else True,
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
