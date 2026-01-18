#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Main Test Runner

Orchestrates all VPN tests and produces comprehensive results.
"""

import json
import os
import sys
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

import yaml

# Add tests directory to path
sys.path.insert(0, str(Path(__file__).parent))

from tests.baseline import measure_baseline, detect_vpn_interface
from tests.latency import run_latency_test, compare_latency
from tests.throughput import run_throughput_test, compare_throughput
from tests.dns_leak import run_dns_leak_test
from tests.ipv6_leak import run_ipv6_leak_test
from tests.ads_blocking import run_ad_blocking_test
from tests.stability import run_stability_test


def load_config() -> Dict[str, Any]:
    """Load configuration from config.yaml"""
    config_path = Path(__file__).parent / 'config.yaml'

    if config_path.exists():
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)

    # Default config if file doesn't exist
    return {
        'latency': {
            'targets': [
                {'host': '1.1.1.1', 'name': 'cloudflare'},
                {'host': '8.8.8.8', 'name': 'google'},
            ],
            'count': 10,
            'timeout': 5
        },
        'throughput': {
            'download_urls': [
                {'url': 'http://speedtest.tele2.net/10MB.zip', 'name': 'tele2_10mb'},
            ]
        },
        'stability': {
            'duration': 30,
            'check_interval': 2
        },
        'scoring': {
            'latency': 25,
            'throughput': 25,
            'dns_leak': 20,
            'ipv6_leak': 10,
            'ad_blocking': 10,
            'stability': 10
        },
        'thresholds': {
            'max_latency_increase_ms': 50,
            'min_throughput_percent': 70,
            'max_tunnel_drops': 2,
            'overall_pass_score': 70
        }
    }


def calculate_score(results: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate overall VPN quality score based on test results.
    """
    weights = config.get('scoring', {})
    thresholds = config.get('thresholds', {})

    scores = {
        'latency': 0,
        'throughput': 0,
        'dns_leak': 0,
        'ipv6_leak': 0,
        'ad_blocking': 0,
        'stability': 0
    }

    # Latency score (lower increase = better)
    if 'latency_comparison' in results:
        increase_percent = results['latency_comparison'].get('increase_percent', 100)
        if increase_percent <= 10:
            scores['latency'] = 100
        elif increase_percent <= 25:
            scores['latency'] = 80
        elif increase_percent <= 50:
            scores['latency'] = 60
        elif increase_percent <= 100:
            scores['latency'] = 40
        else:
            scores['latency'] = 20

    # Throughput score (higher retention = better)
    if 'throughput_comparison' in results:
        retained = results['throughput_comparison'].get('retained_percent', 0)
        if retained >= 90:
            scores['throughput'] = 100
        elif retained >= 75:
            scores['throughput'] = 80
        elif retained >= 60:
            scores['throughput'] = 60
        elif retained >= 40:
            scores['throughput'] = 40
        else:
            scores['throughput'] = 20

    # DNS leak score (no leak = 100)
    if 'dns_leak' in results:
        if not results['dns_leak'].get('leak_detected', True):
            scores['dns_leak'] = 100
        elif results['dns_leak'].get('leak_severity') == 'minor':
            scores['dns_leak'] = 50
        else:
            scores['dns_leak'] = 0

    # IPv6 leak score (no leak = 100)
    if 'ipv6_leak' in results:
        if not results['ipv6_leak'].get('leak_detected', True):
            scores['ipv6_leak'] = 100
        elif results['ipv6_leak'].get('leak_severity') == 'potential':
            scores['ipv6_leak'] = 50
        else:
            scores['ipv6_leak'] = 0

    # Ad blocking score
    if 'ad_blocking' in results:
        blocked_percent = (
            results['ad_blocking'].get('ads_blocked_percent', 0) +
            results['ad_blocking'].get('trackers_blocked_percent', 0)
        ) / 2
        scores['ad_blocking'] = min(100, blocked_percent)

    # Stability score
    if 'stability' in results:
        uptime = results['stability'].get('uptime_percent', 0)
        drops = results['stability'].get('tunnel_drops', 99)
        if uptime >= 99 and drops == 0:
            scores['stability'] = 100
        elif uptime >= 95 and drops <= 1:
            scores['stability'] = 80
        elif uptime >= 90 and drops <= 2:
            scores['stability'] = 60
        else:
            scores['stability'] = max(0, uptime - 20)

    # Calculate weighted overall score
    total_weight = sum(weights.values())
    weighted_score = 0

    for test_name, score in scores.items():
        weight = weights.get(test_name, 0)
        weighted_score += (score * weight) / total_weight if total_weight > 0 else 0

    overall_score = round(weighted_score, 1)

    # Determine pass/fail
    pass_threshold = thresholds.get('overall_pass_score', 70)
    passed = overall_score >= pass_threshold

    return {
        'individual_scores': scores,
        'weights': weights,
        'overall_score': overall_score,
        'pass_threshold': pass_threshold,
        'passed': passed,
        'status': 'PASSED' if passed else 'FAILED'
    }


def run_all_tests(
    skip_baseline: bool = False,
    baseline_data: Optional[Dict[str, Any]] = None,
    stability_duration: int = 30,
    verbose: bool = True
) -> Dict[str, Any]:
    """
    Run complete VPN test suite.

    Args:
        skip_baseline: Skip baseline tests (assume VPN is always on)
        baseline_data: Pre-existing baseline data to use
        stability_duration: Duration for stability test
        verbose: Print progress to console

    Returns:
        Complete test results dictionary
    """
    config = load_config()
    start_time = time.time()

    results = {
        'test_suite': 'SecureWave VPN Test Suite',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'unix_timestamp': start_time,
    }

    def log(msg: str):
        if verbose:
            print(msg)

    # Detect VPN
    log("\n[*] Detecting VPN interface...")
    vpn_interface = detect_vpn_interface()
    results['vpn_detected'] = vpn_interface is not None
    results['vpn_interface'] = vpn_interface

    if vpn_interface:
        log(f"[+] VPN interface detected: {vpn_interface}")
    else:
        log("[!] No VPN interface detected")
        log("    Tests will run but may not reflect VPN performance")

    # Baseline measurements
    if not skip_baseline and baseline_data is None:
        log("\n[*] Running baseline measurements...")
        log("    (For accurate baseline, VPN should be disconnected)")

        baseline = measure_baseline(
            ping_targets=config.get('latency', {}).get('targets'),
            download_urls=config.get('throughput', {}).get('download_urls'),
            ping_count=config.get('latency', {}).get('count', 10)
        )
        results['baseline'] = asdict(baseline)
        log(f"    Baseline latency: {baseline.latency_ms:.2f} ms")
        log(f"    Baseline throughput: {baseline.throughput_mbps:.2f} Mbps")
    elif baseline_data:
        results['baseline'] = baseline_data
        log("\n[*] Using provided baseline data")

    # Latency test
    log("\n[*] Running latency test...")
    latency_result = run_latency_test(
        targets=config.get('latency', {}).get('targets'),
        ping_count=config.get('latency', {}).get('count', 10)
    )
    results['latency'] = asdict(latency_result)
    log(f"    Average latency: {latency_result.avg_latency_ms:.2f} ms")
    log(f"    Jitter: {latency_result.jitter_ms:.2f} ms")

    # Compare to baseline if available
    if 'baseline' in results:
        comparison = compare_latency(
            results['baseline'].get('latency_ms', 0),
            latency_result.avg_latency_ms
        )
        results['latency_comparison'] = comparison
        log(f"    vs Baseline: +{comparison['difference_ms']:.2f} ms ({comparison['rating']})")

    # Throughput test
    log("\n[*] Running throughput test...")
    log("    Downloading test files...")
    throughput_result = run_throughput_test(
        download_urls=config.get('throughput', {}).get('download_urls')
    )
    results['throughput'] = asdict(throughput_result)
    log(f"    Average download: {throughput_result.avg_download_mbps:.2f} Mbps")

    # Compare to baseline
    if 'baseline' in results:
        comparison = compare_throughput(
            results['baseline'].get('throughput_mbps', 0),
            throughput_result.avg_download_mbps
        )
        results['throughput_comparison'] = comparison
        log(f"    vs Baseline: {comparison['retained_percent']:.1f}% retained ({comparison['rating']})")

    # DNS leak test
    log("\n[*] Running DNS leak detection...")
    dns_result = run_dns_leak_test()
    results['dns_leak'] = asdict(dns_result)
    if dns_result.leak_detected:
        log(f"    [!] DNS leak detected: {dns_result.leak_severity}")
    else:
        log("    [+] No DNS leaks detected")

    # IPv6 leak test
    log("\n[*] Running IPv6 leak detection...")
    ipv6_result = run_ipv6_leak_test()
    results['ipv6_leak'] = asdict(ipv6_result)
    if ipv6_result.leak_detected:
        log(f"    [!] IPv6 leak detected: {ipv6_result.leak_severity}")
    else:
        log("    [+] No IPv6 leaks detected")

    # Ad blocking test
    log("\n[*] Running ad/tracker blocking test...")
    ad_result = run_ad_blocking_test()
    results['ad_blocking'] = asdict(ad_result)
    total_blocked = ad_result.ads_blocked + ad_result.trackers_blocked
    total = ad_result.ads_total + ad_result.trackers_total
    log(f"    Blocked: {total_blocked}/{total} ({ad_result.effectiveness_rating})")

    # Stability test
    log(f"\n[*] Running stability test ({stability_duration}s)...")
    stability_result = run_stability_test(
        duration_seconds=stability_duration,
        check_interval=config.get('stability', {}).get('check_interval', 2)
    )
    results['stability'] = asdict(stability_result)
    log(f"    Uptime: {stability_result.uptime_percent:.1f}%")
    log(f"    Tunnel drops: {stability_result.tunnel_drops}")
    log(f"    Rating: {stability_result.stability_rating}")

    # Calculate overall score
    log("\n[*] Calculating overall score...")
    score_result = calculate_score(results, config)
    results['scoring'] = score_result
    log(f"    Overall Score: {score_result['overall_score']}/100")
    log(f"    Status: {score_result['status']}")

    # Test duration
    results['test_duration_seconds'] = round(time.time() - start_time, 2)

    return results


def print_summary(results: Dict[str, Any]):
    """Print formatted test summary to console."""
    print("\n" + "=" * 50)
    print("[+] SecureWave VPN Test Suite")
    print("=" * 50)

    # Baseline vs VPN comparison
    baseline = results.get('baseline', {})
    latency = results.get('latency', {})
    throughput = results.get('throughput', {})
    latency_cmp = results.get('latency_comparison', {})
    throughput_cmp = results.get('throughput_comparison', {})

    print(f"\nBaseline latency:        {baseline.get('latency_ms', 'N/A')} ms")
    if latency:
        diff = latency_cmp.get('difference_ms', 0)
        sign = '+' if diff >= 0 else ''
        print(f"SecureWave latency:      {latency.get('avg_latency_ms', 'N/A')} ms ({sign}{diff:.1f})")

    print(f"\nBaseline download:       {baseline.get('throughput_mbps', 'N/A')} Mbps")
    if throughput:
        retained = throughput_cmp.get('retained_percent', 0)
        print(f"SecureWave download:     {throughput.get('avg_download_mbps', 'N/A')} Mbps ({retained:.0f}%)")

    # Leak detection
    dns_leak = results.get('dns_leak', {})
    ipv6_leak = results.get('ipv6_leak', {})

    print(f"\nDNS leaks detected:      {'YES' if dns_leak.get('leak_detected') else 'NO'}")
    print(f"IPv6 leaks detected:     {'YES' if ipv6_leak.get('leak_detected') else 'NO'}")

    # Ad blocking
    ad_blocking = results.get('ad_blocking', {})
    if ad_blocking:
        print(f"\nAds blocked:             {ad_blocking.get('ads_blocked_percent', 0):.0f}%")
        print(f"Trackers blocked:        {ad_blocking.get('trackers_blocked_percent', 0):.0f}%")

    # Stability
    stability = results.get('stability', {})
    if stability:
        print(f"\nTunnel drops:            {stability.get('tunnel_drops', 'N/A')}")
        avg_reconnect = stability.get('avg_reconnect_time_seconds', 0)
        if avg_reconnect > 0:
            print(f"Avg reconnect time:      {avg_reconnect:.1f} s")

    # Final score
    scoring = results.get('scoring', {})
    print(f"\nOVERALL SCORE:           {scoring.get('overall_score', 0)}/100")
    print(f"STATUS:                  {scoring.get('status', 'UNKNOWN')}")
    print("-" * 50)
    print(f"Results saved to results/latest.json")


def save_results(results: Dict[str, Any], output_dir: Optional[str] = None):
    """Save results to JSON file."""
    if output_dir is None:
        output_dir = Path(__file__).parent / 'results'

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save as latest.json
    latest_path = output_dir / 'latest.json'
    with open(latest_path, 'w') as f:
        json.dump(results, f, indent=2, default=str)

    # Also save timestamped version
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    timestamped_path = output_dir / f'results_{timestamp}.json'
    with open(timestamped_path, 'w') as f:
        json.dump(results, f, indent=2, default=str)

    return str(latest_path)


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description='SecureWave VPN Test Suite')
    parser.add_argument('--skip-baseline', action='store_true',
                        help='Skip baseline measurements')
    parser.add_argument('--stability-duration', type=int, default=30,
                        help='Stability test duration in seconds')
    parser.add_argument('--output-dir', type=str, default=None,
                        help='Output directory for results')
    parser.add_argument('--quiet', action='store_true',
                        help='Minimal output')
    parser.add_argument('--json', action='store_true',
                        help='Output JSON only')

    args = parser.parse_args()

    # Run tests
    results = run_all_tests(
        skip_baseline=args.skip_baseline,
        stability_duration=args.stability_duration,
        verbose=not args.quiet and not args.json
    )

    # Save results
    output_path = save_results(results, args.output_dir)

    # Print output
    if args.json:
        print(json.dumps(results, indent=2, default=str))
    else:
        print_summary(results)


if __name__ == '__main__':
    main()
