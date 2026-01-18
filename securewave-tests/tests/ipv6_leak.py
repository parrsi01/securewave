#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - IPv6 Leak Detection
Detects if IPv6 traffic is leaking outside the VPN tunnel.
"""

import subprocess
import socket
import time
from dataclasses import dataclass
from typing import List, Dict, Any, Optional

from .baseline import detect_vpn_interface


@dataclass
class IPv6LeakResult:
    """IPv6 leak test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    ipv6_enabled: bool
    leak_detected: bool
    leak_severity: str  # none, potential, confirmed
    ipv6_addresses: List[str]
    ipv6_connectivity: bool
    test_results: List[Dict[str, Any]]
    timestamp: float
    recommendation: str


def get_ipv6_addresses() -> List[str]:
    """
    Get all IPv6 addresses configured on the system.
    """
    addresses = []

    try:
        result = subprocess.run(
            ['ip', '-6', 'addr', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'inet6' in line and 'scope global' in line:
                    # Extract IPv6 address
                    parts = line.strip().split()
                    for i, part in enumerate(parts):
                        if part == 'inet6' and i + 1 < len(parts):
                            addr = parts[i + 1].split('/')[0]
                            # Skip link-local (fe80::) addresses
                            if not addr.startswith('fe80'):
                                addresses.append(addr)
    except Exception:
        pass

    return addresses


def check_ipv6_connectivity(target: str, timeout: int = 5) -> Dict[str, Any]:
    """
    Check IPv6 connectivity to a target.
    """
    result = {
        'target': target,
        'reachable': False,
        'response_time_ms': 0,
        'error': None,
        'timestamp': time.time()
    }

    try:
        start_time = time.time()

        # Try to ping the IPv6 address
        proc = subprocess.run(
            ['ping', '-6', '-c', '1', '-W', str(timeout), target],
            capture_output=True,
            text=True,
            timeout=timeout + 2
        )

        response_time = (time.time() - start_time) * 1000

        if proc.returncode == 0:
            result['reachable'] = True
            result['response_time_ms'] = round(response_time, 2)
        else:
            result['error'] = 'no response'

    except subprocess.TimeoutExpired:
        result['error'] = 'timeout'
    except Exception as e:
        result['error'] = str(e)

    return result


def check_ipv6_route_leak() -> Dict[str, Any]:
    """
    Check if IPv6 traffic has a route that bypasses VPN.
    """
    result = {
        'has_default_route': False,
        'route_via_vpn': False,
        'route_interface': None,
        'route_gateway': None
    }

    try:
        proc = subprocess.run(
            ['ip', '-6', 'route', 'show', 'default'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if proc.returncode == 0 and proc.stdout.strip():
            result['has_default_route'] = True

            output = proc.stdout.strip()

            # Extract interface
            if 'dev' in output:
                parts = output.split()
                for i, part in enumerate(parts):
                    if part == 'dev' and i + 1 < len(parts):
                        iface = parts[i + 1]
                        result['route_interface'] = iface

                        # Check if it's a VPN interface
                        vpn_patterns = ['wg', 'tun', 'utun', 'ppp']
                        result['route_via_vpn'] = any(p in iface for p in vpn_patterns)

            # Extract gateway
            if 'via' in output:
                parts = output.split()
                for i, part in enumerate(parts):
                    if part == 'via' and i + 1 < len(parts):
                        result['route_gateway'] = parts[i + 1]

    except Exception:
        pass

    return result


def run_ipv6_leak_test(
    test_targets: List[str] = None
) -> IPv6LeakResult:
    """
    Run comprehensive IPv6 leak detection test.

    Args:
        test_targets: List of IPv6 addresses to test connectivity to

    Returns:
        IPv6LeakResult with leak detection results
    """
    timestamp = time.time()

    # Default IPv6 test targets
    if test_targets is None:
        test_targets = [
            '2001:4860:4860::8888',  # Google IPv6 DNS
            '2606:4700:4700::1111',  # Cloudflare IPv6 DNS
        ]

    # Detect VPN
    vpn_interface = detect_vpn_interface()
    vpn_detected = vpn_interface is not None

    # Get IPv6 addresses
    ipv6_addresses = get_ipv6_addresses()
    ipv6_enabled = len(ipv6_addresses) > 0

    # Check IPv6 routing
    route_check = check_ipv6_route_leak()

    # Test IPv6 connectivity
    test_results = []
    ipv6_connectivity = False

    for target in test_targets:
        result = check_ipv6_connectivity(target)
        test_results.append(result)
        if result['reachable']:
            ipv6_connectivity = True

    # Determine leak status
    if not vpn_detected:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'No VPN detected. Connect to VPN before running leak tests.'
    elif not ipv6_enabled and not ipv6_connectivity:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'IPv6 is disabled or not available. No IPv6 leak possible.'
    elif ipv6_enabled and not ipv6_connectivity:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'IPv6 configured but not reachable. VPN may be blocking IPv6 correctly.'
    elif route_check['has_default_route'] and not route_check['route_via_vpn']:
        leak_detected = True
        leak_severity = 'confirmed'
        recommendation = f"IPv6 leak confirmed. Default IPv6 route via {route_check['route_interface']} bypasses VPN."
    elif ipv6_connectivity and not route_check['route_via_vpn']:
        leak_detected = True
        leak_severity = 'confirmed'
        recommendation = 'IPv6 connectivity detected outside VPN tunnel. This is a leak.'
    elif ipv6_connectivity and route_check['route_via_vpn']:
        leak_detected = False
        leak_severity = 'none'
        recommendation = 'IPv6 traffic appears to route through VPN. No leak detected.'
    else:
        leak_detected = False
        leak_severity = 'potential'
        recommendation = 'Unable to determine IPv6 leak status. Manual verification recommended.'

    return IPv6LeakResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_detected,
        ipv6_enabled=ipv6_enabled,
        leak_detected=leak_detected,
        leak_severity=leak_severity,
        ipv6_addresses=ipv6_addresses,
        ipv6_connectivity=ipv6_connectivity,
        test_results=test_results,
        timestamp=timestamp,
        recommendation=recommendation
    )


if __name__ == '__main__':
    print("Running IPv6 leak detection test...")

    result = run_ipv6_leak_test()

    print(f"\nIPv6 Leak Test Results:")
    print(f"  VPN Detected:        {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:       {result.vpn_interface}")
    print(f"  IPv6 Enabled:        {result.ipv6_enabled}")
    print(f"  IPv6 Connectivity:   {result.ipv6_connectivity}")
    print(f"  Leak Detected:       {result.leak_detected}")
    print(f"  Severity:            {result.leak_severity}")
    if result.ipv6_addresses:
        print(f"  IPv6 Addresses:      {', '.join(result.ipv6_addresses)}")
    print(f"\n  Recommendation: {result.recommendation}")
