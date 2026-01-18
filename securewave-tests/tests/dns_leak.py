#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - DNS Leak Detection
Detects if DNS queries are leaking outside the VPN tunnel.
"""

import subprocess
import socket
import time
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional, Set

from .baseline import detect_vpn_interface


@dataclass
class DNSLeakResult:
    """DNS leak test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    leak_detected: bool
    leak_severity: str  # none, minor, major, critical
    resolvers_detected: List[str]
    expected_resolvers: List[str]
    unexpected_resolvers: List[str]
    test_queries: List[Dict[str, Any]]
    timestamp: float
    recommendation: str


def get_system_dns_servers() -> List[str]:
    """
    Get configured DNS servers from the system.
    """
    dns_servers = []

    # Try reading /etc/resolv.conf
    try:
        with open('/etc/resolv.conf', 'r') as f:
            for line in f:
                if line.strip().startswith('nameserver'):
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        dns_servers.append(parts[1])
    except Exception:
        pass

    # Try systemd-resolve
    try:
        result = subprocess.run(
            ['systemd-resolve', '--status'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'DNS Servers:' in line or 'Current DNS Server:' in line:
                    parts = line.split(':')
                    if len(parts) >= 2:
                        servers = parts[1].strip().split()
                        dns_servers.extend(servers)
    except Exception:
        pass

    # Remove duplicates while preserving order
    seen = set()
    unique_servers = []
    for server in dns_servers:
        if server not in seen and server:
            seen.add(server)
            unique_servers.append(server)

    return unique_servers


def query_dns_resolver_identity(domain: str, timeout: int = 5) -> Optional[str]:
    """
    Query special domains that reveal the resolver's IP.

    Some domains return the IP of the DNS resolver querying them:
    - whoami.akamai.net (returns resolver IP in TXT)
    - myip.opendns.com (returns client IP in A record when using OpenDNS)
    """
    try:
        result = subprocess.run(
            ['dig', '+short', domain, 'TXT', '+time=' + str(timeout)],
            capture_output=True,
            text=True,
            timeout=timeout + 2
        )
        if result.returncode == 0 and result.stdout.strip():
            # Clean up the response (remove quotes)
            response = result.stdout.strip().replace('"', '')
            return response
    except Exception:
        pass

    return None


def resolve_domain(domain: str, timeout: int = 5) -> Dict[str, Any]:
    """
    Resolve a domain and track which resolver was used.
    """
    result = {
        'domain': domain,
        'resolved_ips': [],
        'resolver_used': None,
        'success': False,
        'response_time_ms': 0,
        'timestamp': time.time()
    }

    start_time = time.time()

    try:
        # Use dig with trace to see resolver
        proc = subprocess.run(
            ['dig', '+short', '+time=' + str(timeout), domain],
            capture_output=True,
            text=True,
            timeout=timeout + 2
        )

        response_time = (time.time() - start_time) * 1000

        if proc.returncode == 0:
            ips = [line.strip() for line in proc.stdout.split('\n') if line.strip()]
            result['resolved_ips'] = ips
            result['success'] = len(ips) > 0
            result['response_time_ms'] = round(response_time, 2)
    except Exception:
        pass

    return result


def run_dns_leak_test(
    expected_resolvers: List[str] = None,
    test_domains: List[str] = None
) -> DNSLeakResult:
    """
    Run comprehensive DNS leak detection test.

    Args:
        expected_resolvers: List of DNS server IPs that should be used when VPN is active
        test_domains: Domains to query during testing

    Returns:
        DNSLeakResult with leak detection results
    """
    timestamp = time.time()

    # Default expected VPN resolvers
    if expected_resolvers is None:
        expected_resolvers = [
            '1.1.1.1', '1.0.0.1',       # Cloudflare
            '10.0.0.1',                   # Common VPN internal
            '10.8.0.1',                   # OpenVPN default
            '10.2.0.1',                   # WireGuard common
        ]

    # Default test domains
    if test_domains is None:
        test_domains = [
            'whoami.akamai.net',
            'google.com',
            'cloudflare.com',
        ]

    # Detect VPN
    vpn_interface = detect_vpn_interface()
    vpn_detected = vpn_interface is not None

    # Get current system DNS servers
    system_dns = get_system_dns_servers()

    # Query resolver identity
    resolver_identity = query_dns_resolver_identity('whoami.akamai.net')

    # Run test queries
    test_queries = []
    for domain in test_domains:
        result = resolve_domain(domain)
        test_queries.append(result)

    # Detect which resolvers are being used
    resolvers_detected: Set[str] = set()

    # Add system DNS servers
    resolvers_detected.update(system_dns)

    # Add resolver identity if found
    if resolver_identity:
        resolvers_detected.add(resolver_identity)

    resolvers_detected = list(resolvers_detected)

    # Determine unexpected resolvers (potential leaks)
    expected_set = set(expected_resolvers)
    unexpected_resolvers = [r for r in resolvers_detected if r not in expected_set]

    # Determine leak severity
    if not vpn_detected:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'No VPN detected. Connect to VPN before running leak tests.'
    elif not unexpected_resolvers:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'No DNS leaks detected. All queries appear to use VPN DNS.'
    elif len(unexpected_resolvers) == 1:
        leak_detected = True
        leak_severity = 'minor'
        recommendation = f'Minor DNS leak detected. Resolver {unexpected_resolvers[0]} may be outside VPN tunnel.'
    elif len(unexpected_resolvers) <= 3:
        leak_detected = True
        leak_severity = 'major'
        recommendation = f'Major DNS leak detected. {len(unexpected_resolvers)} resolvers outside VPN tunnel.'
    else:
        leak_detected = True
        leak_severity = 'critical'
        recommendation = 'Critical DNS leak. Most DNS traffic appears to bypass VPN tunnel.'

    return DNSLeakResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_detected,
        leak_detected=leak_detected,
        leak_severity=leak_severity,
        resolvers_detected=resolvers_detected,
        expected_resolvers=expected_resolvers,
        unexpected_resolvers=unexpected_resolvers,
        test_queries=test_queries,
        timestamp=timestamp,
        recommendation=recommendation
    )


if __name__ == '__main__':
    print("Running DNS leak detection test...")

    result = run_dns_leak_test()

    print(f"\nDNS Leak Test Results:")
    print(f"  VPN Detected:        {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:       {result.vpn_interface}")
    print(f"  Leak Detected:       {result.leak_detected}")
    print(f"  Severity:            {result.leak_severity}")
    print(f"  Resolvers Found:     {', '.join(result.resolvers_detected) or 'none'}")
    if result.unexpected_resolvers:
        print(f"  Unexpected:          {', '.join(result.unexpected_resolvers)}")
    print(f"\n  Recommendation: {result.recommendation}")
