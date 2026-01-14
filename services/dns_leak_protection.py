"""
SecureWave VPN - DNS Leak Protection Service
Implements DNS leak detection and prevention mechanisms
"""

import os
import logging
import socket
import dns.resolver
from typing import List, Dict, Optional, Tuple
from datetime import datetime

logger = logging.getLogger(__name__)

# DNS servers to use for leak-free resolution
SECURE_DNS_SERVERS = [
    "1.1.1.1",  # Cloudflare
    "1.0.0.1",  # Cloudflare
    "8.8.8.8",  # Google
    "8.8.4.4",  # Google
    "9.9.9.9",  # Quad9
]

# DNS servers to avoid (ISP/default that can leak)
KNOWN_ISP_DNS_PATTERNS = [
    "192.168.",  # Local network
    "10.",       # Private network
    "172.",      # Private network
]


class DNSLeakProtectionService:
    """
    DNS Leak Protection Service
    Detects and prevents DNS leaks through VPN tunnels
    """

    def __init__(self):
        """Initialize DNS leak protection service"""
        self.secure_dns_servers = SECURE_DNS_SERVERS.copy()

    # ===========================
    # DNS LEAK DETECTION
    # ===========================

    def detect_dns_leak(self, test_domain: str = "whoami.akamai.net") -> Dict:
        """
        Detect potential DNS leaks

        Args:
            test_domain: Domain to query for leak testing

        Returns:
            Dictionary with leak detection results
        """
        try:
            # Get current DNS servers
            current_dns = self._get_current_dns_servers()

            # Perform DNS query
            resolved_ips = self._resolve_domain(test_domain)

            # Check for leaks
            is_leak_detected = self._check_for_leak(current_dns)

            # Get geographic info of DNS servers
            dns_locations = self._get_dns_locations(current_dns)

            return {
                "leak_detected": is_leak_detected,
                "current_dns_servers": current_dns,
                "resolved_ips": resolved_ips,
                "dns_locations": dns_locations,
                "test_domain": test_domain,
                "timestamp": datetime.utcnow().isoformat(),
                "recommendation": self._get_recommendation(is_leak_detected, current_dns),
            }

        except Exception as e:
            logger.error(f"DNS leak detection failed: {e}")
            return {
                "leak_detected": None,
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            }

    def _get_current_dns_servers(self) -> List[str]:
        """Get currently configured DNS servers"""
        try:
            # Try to read from /etc/resolv.conf (Linux/macOS)
            dns_servers = []

            try:
                with open('/etc/resolv.conf', 'r') as f:
                    for line in f:
                        if line.startswith('nameserver'):
                            server = line.split()[1]
                            dns_servers.append(server)
            except FileNotFoundError:
                # Windows or file doesn't exist
                pass

            # Fallback: use dnspython
            if not dns_servers:
                resolver = dns.resolver.Resolver()
                dns_servers = [str(ns) for ns in resolver.nameservers]

            return dns_servers

        except Exception as e:
            logger.error(f"Failed to get DNS servers: {e}")
            return []

    def _resolve_domain(self, domain: str) -> List[str]:
        """Resolve domain to IP addresses"""
        try:
            answers = dns.resolver.resolve(domain, 'A')
            return [str(rdata) for rdata in answers]
        except Exception as e:
            logger.error(f"DNS resolution failed: {e}")
            return []

    def _check_for_leak(self, dns_servers: List[str]) -> bool:
        """
        Check if DNS servers indicate a leak

        Args:
            dns_servers: List of DNS server IPs

        Returns:
            True if leak detected
        """
        for server in dns_servers:
            # Check if DNS server is a known ISP/private network server
            for pattern in KNOWN_ISP_DNS_PATTERNS:
                if server.startswith(pattern):
                    logger.warning(f"Potential DNS leak detected: {server} (matches pattern {pattern})")
                    return True

            # Check if DNS server is NOT one of our secure servers
            if server not in self.secure_dns_servers:
                # Additional check: is it a public DNS?
                if not self._is_public_dns(server):
                    logger.warning(f"DNS server {server} is not a known secure DNS server")
                    return True

        return False

    def _is_public_dns(self, ip: str) -> bool:
        """Check if IP is a known public DNS server"""
        public_dns_servers = SECURE_DNS_SERVERS + [
            # Add other known public DNS providers
            "208.67.222.222",  # OpenDNS
            "208.67.220.220",  # OpenDNS
            "64.6.64.6",       # Verisign
            "64.6.65.6",       # Verisign
        ]
        return ip in public_dns_servers

    def _get_dns_locations(self, dns_servers: List[str]) -> Dict[str, Dict]:
        """
        Get geographic location of DNS servers
        (Simplified - in production, use a GeoIP service)
        """
        locations = {}
        for server in dns_servers:
            locations[server] = {
                "country": "Unknown",
                "city": "Unknown",
                "isp": "Unknown",
                "is_secure": server in self.secure_dns_servers,
            }
        return locations

    def _get_recommendation(self, leak_detected: bool, dns_servers: List[str]) -> str:
        """Get recommendation based on leak detection"""
        if leak_detected:
            return (
                "DNS leak detected! Your DNS queries may be visible to your ISP. "
                "Ensure your VPN is configured to use secure DNS servers. "
                f"Recommended DNS servers: {', '.join(self.secure_dns_servers[:2])}"
            )
        else:
            return "No DNS leak detected. Your DNS queries are properly secured."

    # ===========================
    # DNS CONFIGURATION
    # ===========================

    def get_recommended_dns_config(self) -> Dict:
        """
        Get recommended DNS configuration for VPN

        Returns:
            Dictionary with DNS configuration
        """
        return {
            "primary_dns": self.secure_dns_servers[0],
            "secondary_dns": self.secure_dns_servers[1],
            "all_secure_dns": self.secure_dns_servers,
            "dns_over_https": {
                "cloudflare": "https://cloudflare-dns.com/dns-query",
                "google": "https://dns.google/dns-query",
                "quad9": "https://dns.quad9.net/dns-query",
            },
            "dns_over_tls": {
                "cloudflare": "cloudflare-dns.com",
                "google": "dns.google",
                "quad9": "dns.quad9.net",
            },
        }

    def generate_wireguard_dns_config(
        self,
        primary_dns: Optional[str] = None,
        secondary_dns: Optional[str] = None
    ) -> str:
        """
        Generate DNS configuration for WireGuard

        Args:
            primary_dns: Primary DNS server (default: Cloudflare)
            secondary_dns: Secondary DNS server (default: Cloudflare)

        Returns:
            DNS configuration string
        """
        primary = primary_dns or self.secure_dns_servers[0]
        secondary = secondary_dns or self.secure_dns_servers[1]

        return f"DNS = {primary}, {secondary}"

    # ===========================
    # DNS LEAK TESTING
    # ===========================

    def run_comprehensive_leak_test(self) -> Dict:
        """
        Run comprehensive DNS leak test

        Returns:
            Detailed test results
        """
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "tests": [],
            "overall_status": "pass",
            "leaks_detected": 0,
        }

        # Test multiple domains
        test_domains = [
            "whoami.akamai.net",
            "dns-leak-test.com",
            "dnsleaktest.org",
        ]

        for domain in test_domains:
            try:
                test_result = self.detect_dns_leak(domain)
                results["tests"].append(test_result)

                if test_result.get("leak_detected"):
                    results["leaks_detected"] += 1
                    results["overall_status"] = "fail"

            except Exception as e:
                logger.error(f"Test failed for {domain}: {e}")
                results["tests"].append({
                    "domain": domain,
                    "error": str(e),
                    "leak_detected": None,
                })

        return results

    # ===========================
    # DNS LEAK PREVENTION
    # ===========================

    def get_leak_prevention_guide(self) -> Dict:
        """
        Get guide for preventing DNS leaks

        Returns:
            Dictionary with prevention steps
        """
        return {
            "wireguard_config": {
                "description": "Add DNS servers to WireGuard configuration",
                "config_line": self.generate_wireguard_dns_config(),
                "example": """
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.8.0.2/32
DNS = 1.1.1.1, 1.0.0.1  # Add this line

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = server.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
            },
            "system_dns_config": {
                "linux": {
                    "description": "Configure system DNS on Linux",
                    "steps": [
                        "Edit /etc/systemd/resolved.conf",
                        "Add: DNS=1.1.1.1 1.0.0.1",
                        "Run: sudo systemctl restart systemd-resolved",
                    ]
                },
                "macos": {
                    "description": "Configure system DNS on macOS",
                    "steps": [
                        "Open System Preferences > Network",
                        "Select your connection",
                        "Click Advanced > DNS",
                        "Add DNS servers: 1.1.1.1 and 1.0.0.1",
                    ]
                },
                "windows": {
                    "description": "Configure system DNS on Windows",
                    "steps": [
                        "Open Network Connections",
                        "Right-click your connection > Properties",
                        "Select Internet Protocol Version 4 (TCP/IPv4)",
                        "Use the following DNS servers:",
                        "Preferred: 1.1.1.1",
                        "Alternate: 1.0.0.1",
                    ]
                },
            },
            "additional_protection": {
                "dns_over_https": "Enable DNS-over-HTTPS in your browser",
                "dns_over_tls": "Use DNS-over-TLS for enhanced privacy",
                "ipv6": "Disable IPv6 if not using IPv6 VPN tunnel",
                "kill_switch": "Enable VPN kill switch to prevent leaks on disconnect",
            },
        }


def get_dns_leak_protection_service() -> DNSLeakProtectionService:
    """Get DNS leak protection service instance"""
    return DNSLeakProtectionService()
