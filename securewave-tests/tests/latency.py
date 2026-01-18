#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Latency & Jitter Tests
Measures latency characteristics with VPN active.
"""

import subprocess
import time
import statistics
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional

from .baseline import detect_vpn_interface, measure_ping, PingResult


@dataclass
class LatencyTestResult:
    """Complete latency test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    avg_latency_ms: float
    min_latency_ms: float
    max_latency_ms: float
    jitter_ms: float
    packet_loss_percent: float
    targets_tested: int
    total_pings: int
    successful_pings: int
    individual_results: List[Dict[str, Any]]
    timestamp: float
    test_duration_seconds: float


def run_latency_test(
    targets: List[Dict[str, str]] = None,
    ping_count: int = 10,
    timeout: int = 5
) -> LatencyTestResult:
    """
    Run comprehensive latency test.

    Args:
        targets: List of {'host': 'x.x.x.x', 'name': 'description'}
        ping_count: Pings per target
        timeout: Timeout per ping in seconds

    Returns:
        LatencyTestResult with all measurements
    """
    start_time = time.time()

    # Default targets
    if targets is None:
        targets = [
            {'host': '1.1.1.1', 'name': 'cloudflare'},
            {'host': '8.8.8.8', 'name': 'google'},
            {'host': '9.9.9.9', 'name': 'quad9'},
        ]

    # Detect VPN
    vpn_interface = detect_vpn_interface()

    # Collect all pings
    all_pings: List[PingResult] = []
    for target in targets:
        pings = measure_ping(
            host=target['host'],
            name=target['name'],
            count=ping_count,
            timeout=timeout
        )
        all_pings.extend(pings)

    # Calculate statistics
    successful_rtts = [p.rtt_ms for p in all_pings if p.success]
    total_pings = len(all_pings)
    successful_count = len(successful_rtts)

    if successful_rtts:
        avg_latency = statistics.mean(successful_rtts)
        min_latency = min(successful_rtts)
        max_latency = max(successful_rtts)
        jitter = statistics.stdev(successful_rtts) if len(successful_rtts) > 1 else 0.0
    else:
        avg_latency = 0.0
        min_latency = 0.0
        max_latency = 0.0
        jitter = 0.0

    packet_loss = ((total_pings - successful_count) / total_pings * 100) if total_pings > 0 else 100.0

    end_time = time.time()

    return LatencyTestResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_interface is not None,
        avg_latency_ms=round(avg_latency, 2),
        min_latency_ms=round(min_latency, 2),
        max_latency_ms=round(max_latency, 2),
        jitter_ms=round(jitter, 2),
        packet_loss_percent=round(packet_loss, 2),
        targets_tested=len(targets),
        total_pings=total_pings,
        successful_pings=successful_count,
        individual_results=[asdict(p) for p in all_pings],
        timestamp=start_time,
        test_duration_seconds=round(end_time - start_time, 2)
    )


def compare_latency(baseline_ms: float, vpn_ms: float) -> Dict[str, Any]:
    """
    Compare baseline latency to VPN latency.

    Returns:
        Dict with comparison metrics
    """
    if baseline_ms <= 0:
        return {
            'baseline_ms': baseline_ms,
            'vpn_ms': vpn_ms,
            'difference_ms': 0,
            'increase_percent': 0,
            'rating': 'unknown'
        }

    difference = vpn_ms - baseline_ms
    increase_percent = (difference / baseline_ms) * 100 if baseline_ms > 0 else 0

    # Rate the increase
    if increase_percent <= 10:
        rating = 'excellent'
    elif increase_percent <= 25:
        rating = 'good'
    elif increase_percent <= 50:
        rating = 'acceptable'
    elif increase_percent <= 100:
        rating = 'poor'
    else:
        rating = 'very_poor'

    return {
        'baseline_ms': baseline_ms,
        'vpn_ms': vpn_ms,
        'difference_ms': round(difference, 2),
        'increase_percent': round(increase_percent, 2),
        'rating': rating
    }


if __name__ == '__main__':
    print("Running latency test...")

    result = run_latency_test()

    print(f"\nLatency Test Results:")
    print(f"  VPN Detected:    {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:   {result.vpn_interface}")
    print(f"  Avg Latency:     {result.avg_latency_ms:.2f} ms")
    print(f"  Min Latency:     {result.min_latency_ms:.2f} ms")
    print(f"  Max Latency:     {result.max_latency_ms:.2f} ms")
    print(f"  Jitter:          {result.jitter_ms:.2f} ms")
    print(f"  Packet Loss:     {result.packet_loss_percent:.1f}%")
    print(f"  Test Duration:   {result.test_duration_seconds:.1f}s")
