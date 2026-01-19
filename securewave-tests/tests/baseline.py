#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Baseline Measurements
Measures network performance without VPN for comparison.

NOTE: This module measures baseline performance. The caller is responsible
for ensuring VPN is disabled before running these tests.
"""

import shutil
import subprocess
import time
import statistics
from dataclasses import dataclass, asdict
from typing import List, Optional, Dict, Any


@dataclass
class PingResult:
    """Single ping measurement result"""
    target: str
    target_name: str
    rtt_ms: float
    success: bool
    timestamp: float


@dataclass
class BaselineMetrics:
    """Complete baseline measurement results"""
    latency_ms: float
    jitter_ms: float
    packet_loss_percent: float
    throughput_mbps: float
    individual_pings: List[Dict[str, Any]]
    download_tests: List[Dict[str, Any]]
    timestamp: float
    vpn_active: bool


def detect_vpn_interface() -> Optional[str]:
    """
    Detect active VPN interface.
    Returns interface name if VPN is detected, None otherwise.
    """
    patterns = ['wg', 'tun', 'utun', 'ppp']

    try:
        if shutil.which('ip'):
            result = subprocess.run(
                ['ip', '-o', 'link', 'show', 'type', 'wireguard'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    parts = line.split(':')
                    if len(parts) >= 2:
                        iface = parts[1].strip().split('@')[0]
                        if iface:
                            return iface
        if shutil.which('wg'):
            result = subprocess.run(
                ['wg', 'show', 'interfaces'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                iface = result.stdout.strip().split()
                if iface:
                    return iface[0]
        if shutil.which('ip'):
            result = subprocess.run(
                ['ip', 'link', 'show'],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    for pattern in patterns:
                        if f': {pattern}' in line:
                            parts = line.split(':')
                            if len(parts) >= 2:
                                iface = parts[1].strip().split('@')[0]
                                if 'UP' in line or 'state UP' in line.upper():
                                    return iface
        elif shutil.which('ifconfig'):
            result = subprocess.run(
                ['ifconfig'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                current_iface = None
                for line in result.stdout.split('\n'):
                    if line and not line.startswith('\t') and not line.startswith(' '):
                        current_iface = line.split(':')[0].strip()
                        for pattern in patterns:
                            if current_iface.startswith(pattern):
                                return current_iface
    except Exception:
        pass

    # Fallback: check with ip route for default via wg/tun
    try:
        if shutil.which('ip'):
            result = subprocess.run(
                ['ip', 'route', 'show', 'default'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for pattern in patterns:
                    if pattern in result.stdout:
                        parts = result.stdout.split()
                        for i, part in enumerate(parts):
                            if part == 'dev' and i + 1 < len(parts):
                                iface = parts[i + 1]
                                if any(p in iface for p in patterns):
                                    return iface
    except Exception:
        pass

    return None


def get_interface_ipv4(interface: str) -> Optional[str]:
    """
    Get IPv4 address for a network interface.
    """
    try:
        if shutil.which('ip'):
            result = subprocess.run(
                ['ip', '-4', 'addr', 'show', interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'inet ' in line:
                        parts = line.strip().split()
                        if len(parts) >= 2:
                            return parts[1].split('/')[0]
        elif shutil.which('ifconfig'):
            result = subprocess.run(
                ['ifconfig', interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    line = line.strip()
                    if line.startswith('inet '):
                        parts = line.split()
                        if len(parts) >= 2:
                            return parts[1]
    except Exception:
        pass
    return None


def get_vpn_tunnel_ip() -> Optional[str]:
    """
    Detect VPN interface and return its IPv4 address if present.
    """
    iface = detect_vpn_interface()
    if not iface:
        return None
    return get_interface_ipv4(iface)


def measure_ping(host: str, name: str, count: int = 10, timeout: int = 5) -> List[PingResult]:
    """
    Measure ping latency to a target host.
    Returns list of individual ping results.
    """
    results = []

    for _ in range(count):
        timestamp = time.time()
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', str(timeout), host],
                capture_output=True,
                text=True,
                timeout=timeout + 1
            )

            if result.returncode == 0:
                # Parse RTT from ping output
                # Format: "time=XX.XXX ms" or "time=XX ms"
                output = result.stdout
                if 'time=' in output:
                    time_part = output.split('time=')[1].split()[0]
                    rtt = float(time_part.replace('ms', ''))
                    results.append(PingResult(
                        target=host,
                        target_name=name,
                        rtt_ms=rtt,
                        success=True,
                        timestamp=timestamp
                    ))
                else:
                    results.append(PingResult(
                        target=host,
                        target_name=name,
                        rtt_ms=0,
                        success=False,
                        timestamp=timestamp
                    ))
            else:
                results.append(PingResult(
                    target=host,
                    target_name=name,
                    rtt_ms=0,
                    success=False,
                    timestamp=timestamp
                ))
        except subprocess.TimeoutExpired:
            results.append(PingResult(
                target=host,
                target_name=name,
                rtt_ms=0,
                success=False,
                timestamp=timestamp
            ))
        except Exception:
            results.append(PingResult(
                target=host,
                target_name=name,
                rtt_ms=0,
                success=False,
                timestamp=timestamp
            ))

        # Small delay between pings
        time.sleep(0.1)

    return results


def measure_throughput_curl(url: str, name: str) -> Dict[str, Any]:
    """
    Measure download throughput using curl.
    Returns speed in Mbps.
    """
    result = {
        'url': url,
        'name': name,
        'speed_mbps': 0.0,
        'success': False,
        'bytes_downloaded': 0,
        'duration_seconds': 0.0,
        'timestamp': time.time()
    }

    try:
        # Use curl with write-out to get timing info
        # Download to /dev/null, measure speed
        start_time = time.time()
        proc = subprocess.run(
            [
                'curl', '-o', '/dev/null', '-s', '-w',
                '%{size_download} %{time_total}',
                '--connect-timeout', '10',
                '--max-time', '30',
                url
            ],
            capture_output=True,
            text=True,
            timeout=35
        )

        if proc.returncode == 0:
            parts = proc.stdout.strip().split()
            if len(parts) >= 2:
                bytes_downloaded = float(parts[0])
                duration = float(parts[1])

                if duration > 0:
                    # Convert bytes/sec to Mbps (megabits per second)
                    speed_mbps = (bytes_downloaded * 8) / (duration * 1_000_000)

                    result['success'] = True
                    result['bytes_downloaded'] = int(bytes_downloaded)
                    result['duration_seconds'] = duration
                    result['speed_mbps'] = round(speed_mbps, 2)
    except subprocess.TimeoutExpired:
        pass
    except Exception:
        pass

    return result


def measure_baseline(
    ping_targets: List[Dict[str, str]] = None,
    download_urls: List[Dict[str, str]] = None,
    ping_count: int = 10
) -> BaselineMetrics:
    """
    Collect complete baseline measurements.

    Args:
        ping_targets: List of {'host': 'x.x.x.x', 'name': 'description'}
        download_urls: List of {'url': '...', 'name': 'description'}
        ping_count: Number of pings per target

    Returns:
        BaselineMetrics with all measurements
    """
    # Default targets if not provided
    if ping_targets is None:
        ping_targets = [
            {'host': '1.1.1.1', 'name': 'cloudflare'},
            {'host': '8.8.8.8', 'name': 'google'},
        ]

    if download_urls is None:
        download_urls = [
            {'url': 'http://speedtest.tele2.net/10MB.zip', 'name': 'tele2_10mb'},
        ]

    # Check if VPN is active
    vpn_interface = detect_vpn_interface()
    vpn_active = vpn_interface is not None

    # Collect ping measurements
    all_pings = []
    for target in ping_targets:
        pings = measure_ping(target['host'], target['name'], count=ping_count)
        all_pings.extend(pings)

    # Calculate latency statistics
    successful_rtts = [p.rtt_ms for p in all_pings if p.success]

    if successful_rtts:
        avg_latency = statistics.mean(successful_rtts)
        jitter = statistics.stdev(successful_rtts) if len(successful_rtts) > 1 else 0.0
    else:
        avg_latency = 0.0
        jitter = 0.0

    # Calculate packet loss
    total_pings = len(all_pings)
    failed_pings = len([p for p in all_pings if not p.success])
    packet_loss = (failed_pings / total_pings * 100) if total_pings > 0 else 100.0

    # Collect throughput measurements
    download_results = []
    for url_info in download_urls:
        result = measure_throughput_curl(url_info['url'], url_info['name'])
        download_results.append(result)

    # Calculate average throughput
    successful_downloads = [d['speed_mbps'] for d in download_results if d['success']]
    avg_throughput = statistics.mean(successful_downloads) if successful_downloads else 0.0

    return BaselineMetrics(
        latency_ms=round(avg_latency, 2),
        jitter_ms=round(jitter, 2),
        packet_loss_percent=round(packet_loss, 2),
        throughput_mbps=round(avg_throughput, 2),
        individual_pings=[asdict(p) for p in all_pings],
        download_tests=download_results,
        timestamp=time.time(),
        vpn_active=vpn_active
    )


if __name__ == '__main__':
    # Run standalone baseline test
    print("Running baseline network measurements...")

    vpn_iface = detect_vpn_interface()
    if vpn_iface:
        print(f"WARNING: VPN interface detected: {vpn_iface}")
        print("For accurate baseline, disable VPN first.")
    else:
        print("No VPN interface detected - good for baseline.")

    metrics = measure_baseline()

    print(f"\nBaseline Results:")
    print(f"  Latency:     {metrics.latency_ms:.2f} ms")
    print(f"  Jitter:      {metrics.jitter_ms:.2f} ms")
    print(f"  Packet Loss: {metrics.packet_loss_percent:.1f}%")
    print(f"  Throughput:  {metrics.throughput_mbps:.2f} Mbps")
    print(f"  VPN Active:  {metrics.vpn_active}")
