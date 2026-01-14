"""
SecureWave VPN - Domain Management Service
Handles custom domain configuration and verification
"""

import os
import logging
import dns.resolver
import socket
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# Configuration
APP_URL = os.getenv("APP_URL", "https://securewave.azurewebsites.net")
DEFAULT_DOMAIN = os.getenv("DEFAULT_DOMAIN", "securewave.azurewebsites.net")
DNS_VERIFICATION_PREFIX = "_securewave-verify"


class DomainManager:
    """
    Domain Management Service
    Handles custom domain setup, verification, and configuration
    """

    def __init__(self):
        """Initialize domain manager"""
        self.default_domain = DEFAULT_DOMAIN
        self.verification_prefix = DNS_VERIFICATION_PREFIX

    # ===========================
    # DOMAIN VERIFICATION
    # ===========================

    def generate_verification_token(self, domain: str) -> str:
        """
        Generate domain verification token

        Args:
            domain: Domain to verify

        Returns:
            Verification token
        """
        import hashlib
        import secrets

        # Generate deterministic but unique token
        salt = secrets.token_hex(16)
        data = f"{domain}:{salt}:{datetime.utcnow().date()}"
        token = hashlib.sha256(data.encode()).hexdigest()[:32]
        return token

    def get_verification_instructions(self, domain: str, token: str) -> Dict:
        """
        Get DNS verification instructions

        Args:
            domain: Domain to verify
            token: Verification token

        Returns:
            Dictionary with verification instructions
        """
        return {
            "domain": domain,
            "token": token,
            "verification_method": "DNS TXT Record",
            "instructions": {
                "step_1": f"Add a TXT record to your DNS configuration",
                "step_2": f"Host/Name: {self.verification_prefix}.{domain}",
                "step_3": f"Value: {token}",
                "step_4": "Wait for DNS propagation (5-30 minutes)",
                "step_5": "Click 'Verify Domain' to complete verification",
            },
            "dns_record": {
                "type": "TXT",
                "host": f"{self.verification_prefix}.{domain}",
                "value": token,
                "ttl": 3600,
            },
            "verification_endpoint": "/api/domains/verify",
        }

    def verify_domain_ownership(self, domain: str, expected_token: str) -> Tuple[bool, Optional[str]]:
        """
        Verify domain ownership via DNS TXT record

        Args:
            domain: Domain to verify
            expected_token: Expected verification token

        Returns:
            Tuple of (is_verified, error_message)
        """
        try:
            verification_host = f"{self.verification_prefix}.{domain}"

            # Query DNS TXT records
            resolver = dns.resolver.Resolver()
            resolver.timeout = 10
            resolver.lifetime = 10

            try:
                answers = resolver.resolve(verification_host, 'TXT')
            except dns.resolver.NXDOMAIN:
                return False, f"DNS record not found: {verification_host}"
            except dns.resolver.NoAnswer:
                return False, f"No TXT record found for {verification_host}"
            except dns.resolver.Timeout:
                return False, "DNS query timeout - please try again"

            # Check if any TXT record matches the token
            for rdata in answers:
                txt_value = rdata.to_text().strip('"')
                if txt_value == expected_token:
                    logger.info(f"Domain verification successful: {domain}")
                    return True, None

            return False, f"Verification token mismatch. Expected: {expected_token}"

        except Exception as e:
            logger.error(f"Domain verification failed for {domain}: {e}")
            return False, f"Verification error: {str(e)}"

    # ===========================
    # DNS CONFIGURATION
    # ===========================

    def get_dns_configuration_guide(self, custom_domain: str) -> Dict:
        """
        Get DNS configuration guide for custom domain

        Args:
            custom_domain: Custom domain (e.g., vpn.example.com)

        Returns:
            Dictionary with DNS configuration instructions
        """
        # Get current Azure app IP (or use default)
        target_ip = self._get_app_ip()

        return {
            "custom_domain": custom_domain,
            "configuration_type": "Azure Web App Custom Domain",
            "dns_records_required": [
                {
                    "type": "A",
                    "host": "@" if custom_domain.count('.') == 1 else custom_domain.split('.')[0],
                    "value": target_ip,
                    "ttl": 3600,
                    "description": "Points your domain to the Azure web app IP",
                },
                {
                    "type": "CNAME",
                    "host": "www" if custom_domain.count('.') == 1 else f"www.{custom_domain.split('.')[0]}",
                    "value": self.default_domain,
                    "ttl": 3600,
                    "description": "Alternative: CNAME to Azure default domain",
                },
            ],
            "recommended_configuration": {
                "method": "CNAME",
                "reason": "More flexible if Azure IP changes",
                "record": {
                    "type": "CNAME",
                    "host": custom_domain,
                    "value": self.default_domain,
                    "ttl": 3600,
                },
            },
            "steps": [
                "1. Log in to your domain registrar (GoDaddy, Namecheap, etc.)",
                "2. Navigate to DNS management",
                f"3. Add CNAME record: {custom_domain} -> {self.default_domain}",
                "4. Wait for DNS propagation (5-30 minutes)",
                "5. Verify domain ownership using TXT record",
                "6. Configure SSL certificate",
            ],
        }

    def check_dns_propagation(self, domain: str, expected_value: str, record_type: str = "A") -> Dict:
        """
        Check if DNS has propagated correctly

        Args:
            domain: Domain to check
            expected_value: Expected DNS value
            record_type: DNS record type (A, CNAME, TXT)

        Returns:
            Dictionary with propagation status
        """
        try:
            resolver = dns.resolver.Resolver()
            resolver.timeout = 5
            resolver.lifetime = 5

            # Query DNS
            try:
                answers = resolver.resolve(domain, record_type)
                resolved_values = [str(rdata) for rdata in answers]

                # Check if expected value is in results
                is_propagated = any(expected_value in val for val in resolved_values)

                return {
                    "domain": domain,
                    "record_type": record_type,
                    "expected_value": expected_value,
                    "resolved_values": resolved_values,
                    "is_propagated": is_propagated,
                    "status": "propagated" if is_propagated else "pending",
                    "checked_at": datetime.utcnow().isoformat(),
                }

            except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
                return {
                    "domain": domain,
                    "record_type": record_type,
                    "expected_value": expected_value,
                    "resolved_values": [],
                    "is_propagated": False,
                    "status": "not_found",
                    "error": "DNS record not found",
                    "checked_at": datetime.utcnow().isoformat(),
                }

        except Exception as e:
            logger.error(f"DNS propagation check failed for {domain}: {e}")
            return {
                "domain": domain,
                "record_type": record_type,
                "is_propagated": False,
                "status": "error",
                "error": str(e),
                "checked_at": datetime.utcnow().isoformat(),
            }

    def _get_app_ip(self) -> str:
        """
        Get the current IP address of the Azure web app

        Returns:
            IP address
        """
        try:
            # Extract hostname from APP_URL
            hostname = self.default_domain
            ip_address = socket.gethostbyname(hostname)
            return ip_address
        except Exception as e:
            logger.warning(f"Failed to resolve app IP: {e}")
            return "0.0.0.0"  # Placeholder

    # ===========================
    # SSL CERTIFICATE SETUP
    # ===========================

    def get_ssl_setup_guide(self, custom_domain: str) -> Dict:
        """
        Get SSL certificate setup guide for custom domain

        Args:
            custom_domain: Custom domain

        Returns:
            Dictionary with SSL setup instructions
        """
        return {
            "custom_domain": custom_domain,
            "ssl_options": [
                {
                    "method": "Azure Managed Certificate",
                    "cost": "Free",
                    "description": "Automatic SSL certificate from Azure",
                    "steps": [
                        "1. Add custom domain in Azure Portal",
                        "2. Navigate to 'TLS/SSL settings'",
                        "3. Click 'Add certificate' -> 'Create App Service Managed Certificate'",
                        "4. Select your custom domain",
                        "5. Add TLS/SSL binding",
                    ],
                    "pros": ["Free", "Auto-renewal", "Easy setup"],
                    "cons": ["Only works with Azure", "Limited customization"],
                    "recommended": True,
                },
                {
                    "method": "Let's Encrypt (Certbot)",
                    "cost": "Free",
                    "description": "Free SSL from Let's Encrypt",
                    "steps": [
                        "1. SSH into your server",
                        "2. Install certbot",
                        "3. Run: certbot certonly --webroot -w /var/www/html -d " + custom_domain,
                        "4. Upload certificate to Azure",
                        "5. Add TLS/SSL binding",
                    ],
                    "pros": ["Free", "Widely trusted", "Full control"],
                    "cons": ["Manual renewal", "More complex setup"],
                    "recommended": False,
                },
                {
                    "method": "Commercial Certificate",
                    "cost": "$50-$200/year",
                    "description": "Purchase from trusted CA (DigiCert, etc.)",
                    "steps": [
                        "1. Purchase certificate from CA",
                        "2. Generate CSR",
                        "3. Verify domain ownership",
                        "4. Download certificate files",
                        "5. Upload to Azure and bind",
                    ],
                    "pros": ["Extended validation options", "Premium support"],
                    "cons": ["Cost", "Manual renewal"],
                    "recommended": False,
                },
            ],
            "azure_portal_steps": {
                "description": "Configure custom domain in Azure Portal",
                "steps": [
                    "1. Open Azure Portal -> App Services",
                    "2. Select 'SecureWave VPN' app",
                    "3. Navigate to 'Custom domains'",
                    "4. Click 'Add custom domain'",
                    f"5. Enter domain: {custom_domain}",
                    "6. Validate domain ownership",
                    "7. Add domain",
                    "8. Navigate to 'TLS/SSL settings'",
                    "9. Create managed certificate",
                    "10. Add HTTPS binding",
                ],
            },
        }

    # ===========================
    # DOMAIN HEALTH CHECK
    # ===========================

    def check_domain_health(self, domain: str) -> Dict:
        """
        Comprehensive domain health check

        Args:
            domain: Domain to check

        Returns:
            Dictionary with health check results
        """
        results = {
            "domain": domain,
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {},
            "overall_status": "healthy",
            "issues": [],
        }

        # Check DNS resolution
        try:
            ip = socket.gethostbyname(domain)
            results["checks"]["dns_resolution"] = {
                "status": "pass",
                "ip_address": ip,
            }
        except Exception as e:
            results["checks"]["dns_resolution"] = {
                "status": "fail",
                "error": str(e),
            }
            results["overall_status"] = "unhealthy"
            results["issues"].append("DNS resolution failed")

        # Check HTTP accessibility
        try:
            import urllib.request
            url = f"http://{domain}"
            req = urllib.request.Request(url, method='HEAD')
            response = urllib.request.urlopen(req, timeout=10)
            results["checks"]["http_accessible"] = {
                "status": "pass",
                "status_code": response.status,
            }
        except Exception as e:
            results["checks"]["http_accessible"] = {
                "status": "fail",
                "error": str(e),
            }
            results["issues"].append("HTTP not accessible")

        # Check HTTPS accessibility and certificate
        try:
            import urllib.request
            import ssl
            url = f"https://{domain}"
            req = urllib.request.Request(url, method='HEAD')
            context = ssl.create_default_context()
            response = urllib.request.urlopen(req, timeout=10, context=context)
            results["checks"]["https_accessible"] = {
                "status": "pass",
                "status_code": response.status,
            }
            results["checks"]["ssl_certificate"] = {
                "status": "pass",
                "valid": True,
            }
        except ssl.SSLCertVerificationError as e:
            results["checks"]["https_accessible"] = {
                "status": "fail",
                "error": "SSL certificate invalid",
            }
            results["checks"]["ssl_certificate"] = {
                "status": "fail",
                "valid": False,
                "error": str(e),
            }
            results["overall_status"] = "degraded"
            results["issues"].append("Invalid SSL certificate")
        except Exception as e:
            results["checks"]["https_accessible"] = {
                "status": "fail",
                "error": str(e),
            }
            results["issues"].append("HTTPS not accessible")

        # Check CNAME record
        try:
            resolver = dns.resolver.Resolver()
            answers = resolver.resolve(domain, 'CNAME')
            cname_target = str(answers[0].target)
            results["checks"]["cname_record"] = {
                "status": "pass",
                "target": cname_target,
            }
        except dns.resolver.NoAnswer:
            results["checks"]["cname_record"] = {
                "status": "info",
                "message": "Using A record instead of CNAME",
            }
        except Exception as e:
            results["checks"]["cname_record"] = {
                "status": "info",
                "message": "No CNAME record",
            }

        return results

    # ===========================
    # AZURE CONFIGURATION
    # ===========================

    def get_azure_cli_commands(self, custom_domain: str, resource_group: str, app_name: str) -> Dict:
        """
        Get Azure CLI commands for custom domain setup

        Args:
            custom_domain: Custom domain
            resource_group: Azure resource group
            app_name: Azure app service name

        Returns:
            Dictionary with Azure CLI commands
        """
        return {
            "custom_domain": custom_domain,
            "resource_group": resource_group,
            "app_name": app_name,
            "prerequisites": {
                "install_azure_cli": "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli",
                "login_command": "az login",
            },
            "commands": {
                "verify_domain": f"az webapp config hostname add --webapp-name {app_name} --resource-group {resource_group} --hostname {custom_domain}",
                "create_managed_certificate": f"az webapp config ssl create --resource-group {resource_group} --name {app_name} --hostname {custom_domain}",
                "bind_certificate": f"az webapp config ssl bind --certificate-thumbprint <thumbprint> --ssl-type SNI --name {app_name} --resource-group {resource_group}",
                "list_hostnames": f"az webapp config hostname list --webapp-name {app_name} --resource-group {resource_group}",
                "list_certificates": f"az webapp config ssl list --resource-group {resource_group}",
            },
            "example_workflow": [
                "# Step 1: Add custom domain",
                f"az webapp config hostname add --webapp-name {app_name} --resource-group {resource_group} --hostname {custom_domain}",
                "",
                "# Step 2: Create managed certificate",
                f"az webapp config ssl create --resource-group {resource_group} --name {app_name} --hostname {custom_domain}",
                "",
                "# Step 3: Get certificate thumbprint",
                f"az webapp config ssl list --resource-group {resource_group}",
                "",
                "# Step 4: Bind certificate (replace <thumbprint>)",
                f"az webapp config ssl bind --certificate-thumbprint <thumbprint> --ssl-type SNI --name {app_name} --resource-group {resource_group}",
            ],
        }


def get_domain_manager() -> DomainManager:
    """Get domain manager instance"""
    return DomainManager()
