"""
SecureWave VPN Test Suite - Test Modules

This package contains individual test modules for VPN performance
and security testing.

Modules:
- baseline: Baseline network measurements (no VPN)
- latency: Latency and jitter tests
- throughput: Download/upload speed tests
- dns_leak: DNS leak detection
- ipv6_leak: IPv6 leak detection
- ads_blocking: Ad/tracker blocking effectiveness
- stability: Tunnel stability monitoring
"""

from .baseline import measure_baseline, detect_vpn_interface, BaselineMetrics
from .latency import run_latency_test, compare_latency, LatencyTestResult
from .throughput import run_throughput_test, compare_throughput, ThroughputTestResult
from .dns_leak import run_dns_leak_test, DNSLeakResult
from .ipv6_leak import run_ipv6_leak_test, IPv6LeakResult
from .ads_blocking import run_ad_blocking_test, AdBlockingResult
from .stability import run_stability_test, StabilityTestResult

__all__ = [
    # Baseline
    'measure_baseline',
    'detect_vpn_interface',
    'BaselineMetrics',
    # Latency
    'run_latency_test',
    'compare_latency',
    'LatencyTestResult',
    # Throughput
    'run_throughput_test',
    'compare_throughput',
    'ThroughputTestResult',
    # DNS Leak
    'run_dns_leak_test',
    'DNSLeakResult',
    # IPv6 Leak
    'run_ipv6_leak_test',
    'IPv6LeakResult',
    # Ad Blocking
    'run_ad_blocking_test',
    'AdBlockingResult',
    # Stability
    'run_stability_test',
    'StabilityTestResult',
]
