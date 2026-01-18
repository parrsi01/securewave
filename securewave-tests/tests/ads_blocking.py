#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Ad & Tracker Blocking Tests
Tests if the VPN's DNS blocks known ad/tracker domains.
"""

import subprocess
import socket
import time
from dataclasses import dataclass
from typing import List, Dict, Any, Optional

from .baseline import detect_vpn_interface


@dataclass
class AdBlockingResult:
    """Ad/tracker blocking test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    blocking_enabled: bool
    ads_blocked: int
    ads_total: int
    ads_blocked_percent: float
    trackers_blocked: int
    trackers_total: int
    trackers_blocked_percent: float
    control_domains_accessible: int
    control_domains_total: int
    blocked_domains: List[str]
    leaked_domains: List[str]
    test_results: List[Dict[str, Any]]
    timestamp: float
    effectiveness_rating: str


def test_domain_blocked(domain: str, timeout: int = 3) -> Dict[str, Any]:
    """
    Test if a domain is blocked by DNS.

    A domain is considered blocked if:
    - DNS resolution fails
    - DNS returns a sinkhole IP (0.0.0.0, 127.0.0.1, etc.)
    """
    result = {
        'domain': domain,
        'blocked': False,
        'resolved_ip': None,
        'error': None,
        'timestamp': time.time()
    }

    # Known sinkhole/block IPs
    sinkhole_ips = {
        '0.0.0.0', '127.0.0.1', '::1', '::',
        '0.0.0.0/0', '127.0.0.0', '255.255.255.255',
        # Common ad-blocking DNS sinkholes
        '0.0.0.0', '127.0.0.1', '0::0'
    }

    try:
        # Try DNS resolution using dig
        proc = subprocess.run(
            ['dig', '+short', '+time=' + str(timeout), domain, 'A'],
            capture_output=True,
            text=True,
            timeout=timeout + 2
        )

        if proc.returncode == 0:
            output = proc.stdout.strip()

            if not output:
                # No response = likely blocked
                result['blocked'] = True
                result['error'] = 'NXDOMAIN or no response'
            else:
                # Check if resolved IP is a sinkhole
                resolved_ips = [ip.strip() for ip in output.split('\n') if ip.strip()]

                if resolved_ips:
                    result['resolved_ip'] = resolved_ips[0]

                    # Check if all resolved IPs are sinkholes
                    all_sinkholes = all(ip in sinkhole_ips for ip in resolved_ips)
                    if all_sinkholes:
                        result['blocked'] = True
                    else:
                        result['blocked'] = False
        else:
            # Resolution failed = blocked
            result['blocked'] = True
            result['error'] = 'resolution failed'

    except subprocess.TimeoutExpired:
        result['blocked'] = True
        result['error'] = 'timeout'
    except Exception as e:
        result['error'] = str(e)

    return result


def run_ad_blocking_test(
    blocked_domains: List[str] = None,
    allowed_domains: List[str] = None
) -> AdBlockingResult:
    """
    Run comprehensive ad/tracker blocking test.

    Args:
        blocked_domains: Domains that should be blocked (ads/trackers)
        allowed_domains: Control domains that should NOT be blocked

    Returns:
        AdBlockingResult with blocking effectiveness
    """
    timestamp = time.time()

    # Default ad/tracker domains (should be blocked)
    if blocked_domains is None:
        blocked_domains = [
            # Advertising
            'doubleclick.net',
            'googleadservices.com',
            'googlesyndication.com',
            'ads.yahoo.com',
            'ad.doubleclick.net',
            'pagead2.googlesyndication.com',
            'adservice.google.com',
            'ads.twitter.com',
            # Tracking
            'pixel.facebook.com',
            'facebook.net',
            'analytics.google.com',
            'hotjar.com',
            'mixpanel.com',
            'segment.io',
            'amplitude.com',
            # Telemetry
            'telemetry.microsoft.com',
            'vortex.data.microsoft.com',
            'data.microsoft.com',
        ]

    # Default control domains (should NOT be blocked)
    if allowed_domains is None:
        allowed_domains = [
            'google.com',
            'cloudflare.com',
            'github.com',
            'microsoft.com',
        ]

    # Detect VPN
    vpn_interface = detect_vpn_interface()
    vpn_detected = vpn_interface is not None

    # Test blocked domains (ads/trackers)
    test_results = []
    blocked_list = []
    leaked_list = []

    for domain in blocked_domains:
        result = test_domain_blocked(domain)
        result['category'] = 'ad_tracker'
        test_results.append(result)

        if result['blocked']:
            blocked_list.append(domain)
        else:
            leaked_list.append(domain)

    # Count ad vs tracker (simplified: assume first half are ads, second half trackers)
    mid = len(blocked_domains) // 2
    ads_blocked = len([d for d in blocked_list if blocked_domains.index(d) < mid]) if blocked_list else 0
    trackers_blocked = len([d for d in blocked_list if d not in blocked_domains[:mid]]) if blocked_list else 0

    ads_total = mid
    trackers_total = len(blocked_domains) - mid

    # Test control domains (should be accessible)
    control_accessible = 0
    for domain in allowed_domains:
        result = test_domain_blocked(domain)
        result['category'] = 'control'
        test_results.append(result)

        if not result['blocked']:
            control_accessible += 1

    # Calculate percentages
    total_blocked = len(blocked_domains)
    blocked_count = len(blocked_list)

    if total_blocked > 0:
        blocked_percent = (blocked_count / total_blocked) * 100
    else:
        blocked_percent = 0

    if ads_total > 0:
        ads_blocked_percent = (ads_blocked / ads_total) * 100
    else:
        ads_blocked_percent = 0

    if trackers_total > 0:
        trackers_blocked_percent = (trackers_blocked / trackers_total) * 100
    else:
        trackers_blocked_percent = 0

    # Determine effectiveness rating
    if not vpn_detected:
        blocking_enabled = False
        effectiveness_rating = 'unknown'
    elif blocked_percent >= 90:
        blocking_enabled = True
        effectiveness_rating = 'excellent'
    elif blocked_percent >= 70:
        blocking_enabled = True
        effectiveness_rating = 'good'
    elif blocked_percent >= 50:
        blocking_enabled = True
        effectiveness_rating = 'moderate'
    elif blocked_percent > 0:
        blocking_enabled = True
        effectiveness_rating = 'minimal'
    else:
        blocking_enabled = False
        effectiveness_rating = 'disabled'

    return AdBlockingResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_detected,
        blocking_enabled=blocking_enabled,
        ads_blocked=ads_blocked,
        ads_total=ads_total,
        ads_blocked_percent=round(ads_blocked_percent, 1),
        trackers_blocked=trackers_blocked,
        trackers_total=trackers_total,
        trackers_blocked_percent=round(trackers_blocked_percent, 1),
        control_domains_accessible=control_accessible,
        control_domains_total=len(allowed_domains),
        blocked_domains=blocked_list,
        leaked_domains=leaked_list,
        test_results=test_results,
        timestamp=timestamp,
        effectiveness_rating=effectiveness_rating
    )


if __name__ == '__main__':
    print("Running ad/tracker blocking test...")
    print("Testing DNS resolution of known ad/tracker domains...\n")

    result = run_ad_blocking_test()

    print(f"Ad/Tracker Blocking Test Results:")
    print(f"  VPN Detected:        {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:       {result.vpn_interface}")
    print(f"  Blocking Enabled:    {result.blocking_enabled}")
    print(f"  Ads Blocked:         {result.ads_blocked}/{result.ads_total} ({result.ads_blocked_percent:.0f}%)")
    print(f"  Trackers Blocked:    {result.trackers_blocked}/{result.trackers_total} ({result.trackers_blocked_percent:.0f}%)")
    print(f"  Control Domains OK:  {result.control_domains_accessible}/{result.control_domains_total}")
    print(f"  Effectiveness:       {result.effectiveness_rating}")

    if result.leaked_domains:
        print(f"\n  Not Blocked (leaking):")
        for domain in result.leaked_domains[:5]:
            print(f"    - {domain}")
        if len(result.leaked_domains) > 5:
            print(f"    ... and {len(result.leaked_domains) - 5} more")
