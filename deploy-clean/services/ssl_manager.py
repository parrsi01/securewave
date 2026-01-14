"""
SecureWave VPN - SSL Certificate Management Service
Handles SSL certificate provisioning, renewal, and management using Let's Encrypt
"""

import os
import logging
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, List, Tuple

logger = logging.getLogger(__name__)

# Configuration
DOMAIN = os.getenv("DOMAIN", "localhost")
EMAIL = os.getenv("SSL_EMAIL", os.getenv("ADMIN_EMAIL"))
CERT_PATH = Path("/etc/letsencrypt/live") / DOMAIN
CERTBOT_PATH = "/usr/bin/certbot"
WEBROOT_PATH = Path("/var/www/html")


class SSLManager:
    """
    SSL Certificate Management Service
    Uses Let's Encrypt (certbot) for free SSL certificates
    """

    def __init__(self):
        """Initialize SSL manager"""
        self.domain = DOMAIN
        self.email = EMAIL
        self.cert_path = CERT_PATH

        # Check if certbot is available
        self.certbot_available = self._check_certbot()

    def _check_certbot(self) -> bool:
        """Check if certbot is installed"""
        try:
            result = subprocess.run(
                ["which", "certbot"],
                capture_output=True,
                text=True,
                timeout=5
            )
            available = result.returncode == 0

            if available:
                logger.info("✓ Certbot is available")
            else:
                logger.warning("✗ Certbot not installed. SSL management disabled.")
                logger.info("Install with: sudo apt-get install certbot python3-certbot-nginx")

            return available

        except Exception as e:
            logger.error(f"Error checking certbot: {e}")
            return False

    def obtain_certificate(
        self,
        domain: Optional[str] = None,
        email: Optional[str] = None,
        webroot: bool = True,
        staging: bool = False
    ) -> Tuple[bool, Optional[str]]:
        """
        Obtain SSL certificate from Let's Encrypt

        Args:
            domain: Domain name (defaults to configured domain)
            email: Email for notifications (defaults to configured email)
            webroot: Use webroot authentication (vs standalone)
            staging: Use Let's Encrypt staging server (for testing)

        Returns:
            Tuple of (success, error_message)
        """
        if not self.certbot_available:
            return False, "Certbot not available"

        domain = domain or self.domain
        email = email or self.email

        if not email:
            return False, "Email required for Let's Encrypt notifications"

        if domain == "localhost":
            return False, "Cannot obtain certificate for localhost"

        try:
            # Build certbot command
            cmd = [
                "sudo", "certbot", "certonly",
                "--non-interactive",
                "--agree-tos",
                "--email", email,
                "-d", domain,
            ]

            # Add webroot or standalone
            if webroot:
                cmd.extend(["--webroot", "-w", str(WEBROOT_PATH)])
            else:
                cmd.extend(["--standalone"])

            # Add staging flag for testing
            if staging:
                cmd.append("--staging")

            logger.info(f"Obtaining SSL certificate for {domain}...")

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120
            )

            if result.returncode == 0:
                logger.info(f"✓ SSL certificate obtained for {domain}")
                return True, None
            else:
                error = result.stderr or result.stdout
                logger.error(f"✗ Failed to obtain certificate: {error}")
                return False, error

        except subprocess.TimeoutExpired:
            return False, "Certbot command timed out"
        except Exception as e:
            logger.error(f"Error obtaining certificate: {e}")
            return False, str(e)

    def renew_certificate(self, force: bool = False) -> Tuple[bool, Optional[str]]:
        """
        Renew SSL certificate

        Args:
            force: Force renewal even if not due

        Returns:
            Tuple of (success, error_message)
        """
        if not self.certbot_available:
            return False, "Certbot not available"

        try:
            cmd = ["sudo", "certbot", "renew", "--non-interactive"]

            if force:
                cmd.append("--force-renewal")

            logger.info("Renewing SSL certificates...")

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120
            )

            if result.returncode == 0:
                logger.info("✓ SSL certificates renewed successfully")
                return True, None
            else:
                error = result.stderr or result.stdout
                logger.error(f"✗ Failed to renew certificates: {error}")
                return False, error

        except subprocess.TimeoutExpired:
            return False, "Certbot renew timed out"
        except Exception as e:
            logger.error(f"Error renewing certificates: {e}")
            return False, str(e)

    def get_certificate_info(self, domain: Optional[str] = None) -> Optional[Dict]:
        """
        Get certificate information

        Args:
            domain: Domain name (defaults to configured domain)

        Returns:
            Certificate info dictionary or None
        """
        domain = domain or self.domain
        cert_dir = Path("/etc/letsencrypt/live") / domain

        try:
            cert_file = cert_dir / "fullchain.pem"

            if not cert_file.exists():
                return None

            # Get certificate expiry using openssl
            result = subprocess.run(
                ["openssl", "x509", "-enddate", "-noout", "-in", str(cert_file)],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                # Parse expiry date
                expiry_str = result.stdout.strip().replace("notAfter=", "")
                expiry_date = datetime.strptime(expiry_str, "%b %d %H:%M:%S %Y %Z")

                days_until_expiry = (expiry_date - datetime.now()).days

                return {
                    "domain": domain,
                    "cert_file": str(cert_file),
                    "key_file": str(cert_dir / "privkey.pem"),
                    "chain_file": str(cert_dir / "chain.pem"),
                    "fullchain_file": str(cert_file),
                    "expiry_date": expiry_date.isoformat(),
                    "days_until_expiry": days_until_expiry,
                    "needs_renewal": days_until_expiry < 30,
                    "expired": days_until_expiry < 0,
                }

            return None

        except Exception as e:
            logger.error(f"Error getting certificate info: {e}")
            return None

    def list_certificates(self) -> List[Dict]:
        """
        List all Let's Encrypt certificates

        Returns:
            List of certificate info dictionaries
        """
        if not self.certbot_available:
            return []

        try:
            result = subprocess.run(
                ["sudo", "certbot", "certificates"],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                # Parse certbot certificates output
                # This is a simplified version - actual parsing would be more complex
                certificates = []
                cert_path = Path("/etc/letsencrypt/live")

                if cert_path.exists():
                    for domain_dir in cert_path.iterdir():
                        if domain_dir.is_dir() and domain_dir.name != "README":
                            info = self.get_certificate_info(domain_dir.name)
                            if info:
                                certificates.append(info)

                return certificates

            return []

        except Exception as e:
            logger.error(f"Error listing certificates: {e}")
            return []

    def revoke_certificate(self, domain: Optional[str] = None) -> Tuple[bool, Optional[str]]:
        """
        Revoke SSL certificate

        Args:
            domain: Domain name (defaults to configured domain)

        Returns:
            Tuple of (success, error_message)
        """
        if not self.certbot_available:
            return False, "Certbot not available"

        domain = domain or self.domain

        try:
            cmd = [
                "sudo", "certbot", "revoke",
                "--non-interactive",
                "--cert-name", domain
            ]

            logger.info(f"Revoking SSL certificate for {domain}...")

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode == 0:
                logger.info(f"✓ SSL certificate revoked for {domain}")
                return True, None
            else:
                error = result.stderr or result.stdout
                logger.error(f"✗ Failed to revoke certificate: {error}")
                return False, error

        except subprocess.TimeoutExpired:
            return False, "Certbot revoke timed out"
        except Exception as e:
            logger.error(f"Error revoking certificate: {e}")
            return False, str(e)

    def setup_auto_renewal(self) -> Tuple[bool, Optional[str]]:
        """
        Set up automatic certificate renewal via cron

        Returns:
            Tuple of (success, error_message)
        """
        if not self.certbot_available:
            return False, "Certbot not available"

        try:
            # Check if cron job already exists
            result = subprocess.run(
                ["sudo", "crontab", "-l"],
                capture_output=True,
                text=True,
                timeout=5
            )

            existing_cron = result.stdout if result.returncode == 0 else ""

            if "certbot renew" in existing_cron:
                logger.info("✓ Auto-renewal already configured")
                return True, None

            # Add cron job (runs twice daily as recommended by Let's Encrypt)
            cron_command = "0 0,12 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'"

            new_cron = existing_cron + "\n" + cron_command + "\n"

            # Update crontab
            result = subprocess.run(
                ["sudo", "crontab", "-"],
                input=new_cron,
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                logger.info("✓ Auto-renewal cron job configured")
                return True, None
            else:
                error = result.stderr or "Failed to update crontab"
                return False, error

        except Exception as e:
            logger.error(f"Error setting up auto-renewal: {e}")
            return False, str(e)

    def health_check(self) -> Dict:
        """
        Check SSL manager health

        Returns:
            Health status dictionary
        """
        cert_info = self.get_certificate_info()

        return {
            "status": "healthy" if cert_info and not cert_info.get("expired") else "warning",
            "certbot_available": self.certbot_available,
            "domain": self.domain,
            "certificate": cert_info,
            "needs_renewal": cert_info.get("needs_renewal") if cert_info else None,
        }


# Singleton instance
_ssl_manager = None


def get_ssl_manager() -> SSLManager:
    """Get singleton SSL manager instance"""
    global _ssl_manager
    if _ssl_manager is None:
        _ssl_manager = SSLManager()
    return _ssl_manager
