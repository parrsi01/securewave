#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Throughput Tests
Measures download/upload speeds with VPN active.
"""

import subprocess
import time
import statistics
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional

from .baseline import detect_vpn_interface, measure_throughput_curl


@dataclass
class ThroughputTestResult:
    """Complete throughput test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    avg_download_mbps: float
    max_download_mbps: float
    min_download_mbps: float
    total_bytes_downloaded: int
    tests_run: int
    tests_successful: int
    individual_results: List[Dict[str, Any]]
    iperf_result: Optional[Dict[str, Any]]
    timestamp: float
    test_duration_seconds: float


def run_iperf_test(server: str, port: int = 5201, duration: int = 10) -> Optional[Dict[str, Any]]:
    """
    Run iperf3 test against a server if available.

    Returns:
        Dict with iperf results or None if unavailable
    """
    result = {
        'server': server,
        'port': port,
        'duration': duration,
        'download_mbps': 0.0,
        'upload_mbps': 0.0,
        'success': False,
        'error': None
    }

    # Check if iperf3 is available
    try:
        subprocess.run(['which', 'iperf3'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        result['error'] = 'iperf3 not installed'
        return result

    if not server:
        result['error'] = 'no server configured'
        return result

    try:
        # Download test
        proc = subprocess.run(
            ['iperf3', '-c', server, '-p', str(port), '-t', str(duration), '-R', '-J'],
            capture_output=True,
            text=True,
            timeout=duration + 10
        )

        if proc.returncode == 0:
            import json
            data = json.loads(proc.stdout)
            if 'end' in data and 'sum_received' in data['end']:
                bits_per_sec = data['end']['sum_received'].get('bits_per_second', 0)
                result['download_mbps'] = round(bits_per_sec / 1_000_000, 2)

        # Upload test
        proc = subprocess.run(
            ['iperf3', '-c', server, '-p', str(port), '-t', str(duration), '-J'],
            capture_output=True,
            text=True,
            timeout=duration + 10
        )

        if proc.returncode == 0:
            import json
            data = json.loads(proc.stdout)
            if 'end' in data and 'sum_sent' in data['end']:
                bits_per_sec = data['end']['sum_sent'].get('bits_per_second', 0)
                result['upload_mbps'] = round(bits_per_sec / 1_000_000, 2)

        result['success'] = True

    except subprocess.TimeoutExpired:
        result['error'] = 'timeout'
    except Exception as e:
        result['error'] = str(e)

    return result


def run_throughput_test(
    download_urls: List[Dict[str, str]] = None,
    iperf_server: Optional[str] = None,
    iperf_port: int = 5201,
    iperf_duration: int = 10
) -> ThroughputTestResult:
    """
    Run comprehensive throughput test.

    Args:
        download_urls: List of {'url': '...', 'name': 'description'}
        iperf_server: Optional iperf3 server address
        iperf_port: iperf3 server port
        iperf_duration: iperf3 test duration

    Returns:
        ThroughputTestResult with all measurements
    """
    start_time = time.time()

    # Default URLs
    if download_urls is None:
        download_urls = [
            {'url': 'http://speedtest.tele2.net/10MB.zip', 'name': 'tele2_10mb'},
            {'url': 'http://proof.ovh.net/files/10Mb.dat', 'name': 'ovh_10mb'},
        ]

    # Detect VPN
    vpn_interface = detect_vpn_interface()

    # Run curl-based download tests
    download_results = []
    for url_info in download_urls:
        result = measure_throughput_curl(url_info['url'], url_info['name'])
        download_results.append(result)

    # Calculate statistics
    successful_speeds = [d['speed_mbps'] for d in download_results if d['success']]
    total_bytes = sum(d['bytes_downloaded'] for d in download_results)

    if successful_speeds:
        avg_speed = statistics.mean(successful_speeds)
        max_speed = max(successful_speeds)
        min_speed = min(successful_speeds)
    else:
        avg_speed = 0.0
        max_speed = 0.0
        min_speed = 0.0

    # Run iperf test if configured
    iperf_result = None
    if iperf_server:
        iperf_result = run_iperf_test(iperf_server, iperf_port, iperf_duration)

    end_time = time.time()

    return ThroughputTestResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_interface is not None,
        avg_download_mbps=round(avg_speed, 2),
        max_download_mbps=round(max_speed, 2),
        min_download_mbps=round(min_speed, 2),
        total_bytes_downloaded=total_bytes,
        tests_run=len(download_results),
        tests_successful=len(successful_speeds),
        individual_results=download_results,
        iperf_result=iperf_result,
        timestamp=start_time,
        test_duration_seconds=round(end_time - start_time, 2)
    )


def compare_throughput(baseline_mbps: float, vpn_mbps: float) -> Dict[str, Any]:
    """
    Compare baseline throughput to VPN throughput.

    Returns:
        Dict with comparison metrics
    """
    if baseline_mbps <= 0:
        return {
            'baseline_mbps': baseline_mbps,
            'vpn_mbps': vpn_mbps,
            'difference_mbps': 0,
            'retained_percent': 0,
            'rating': 'unknown'
        }

    retained_percent = (vpn_mbps / baseline_mbps) * 100

    # Rate the retention
    if retained_percent >= 90:
        rating = 'excellent'
    elif retained_percent >= 75:
        rating = 'good'
    elif retained_percent >= 60:
        rating = 'acceptable'
    elif retained_percent >= 40:
        rating = 'poor'
    else:
        rating = 'very_poor'

    return {
        'baseline_mbps': baseline_mbps,
        'vpn_mbps': vpn_mbps,
        'difference_mbps': round(vpn_mbps - baseline_mbps, 2),
        'retained_percent': round(retained_percent, 2),
        'rating': rating
    }


if __name__ == '__main__':
    print("Running throughput test...")
    print("This may take a minute to download test files...\n")

    result = run_throughput_test()

    print(f"Throughput Test Results:")
    print(f"  VPN Detected:      {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:     {result.vpn_interface}")
    print(f"  Avg Download:      {result.avg_download_mbps:.2f} Mbps")
    print(f"  Max Download:      {result.max_download_mbps:.2f} Mbps")
    print(f"  Min Download:      {result.min_download_mbps:.2f} Mbps")
    print(f"  Tests Successful:  {result.tests_successful}/{result.tests_run}")
    print(f"  Test Duration:     {result.test_duration_seconds:.1f}s")

    if result.iperf_result and result.iperf_result.get('success'):
        print(f"\n  iperf3 Results:")
        print(f"    Download:        {result.iperf_result['download_mbps']:.2f} Mbps")
        print(f"    Upload:          {result.iperf_result['upload_mbps']:.2f} Mbps")
