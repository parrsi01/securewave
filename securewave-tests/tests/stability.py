#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Tunnel Stability Tests
Monitors VPN tunnel stability over time.
"""

import shutil
import subprocess
import time
from dataclasses import dataclass
from typing import List, Dict, Any, Optional

from .baseline import detect_vpn_interface


@dataclass
class StabilityTestResult:
    """Tunnel stability test results"""
    vpn_interface: Optional[str]
    vpn_detected: bool
    test_duration_seconds: float
    checks_performed: int
    tunnel_drops: int
    reconnections: int
    avg_reconnect_time_seconds: float
    max_reconnect_time_seconds: float
    uptime_percent: float
    connectivity_checks: List[Dict[str, Any]]
    interface_changes: List[Dict[str, Any]]
    timestamp: float
    stability_rating: str


def check_vpn_status() -> Dict[str, Any]:
    """
    Check current VPN tunnel status.
    """
    result = {
        'interface': None,
        'active': False,
        'rx_bytes': 0,
        'tx_bytes': 0,
        'timestamp': time.time()
    }

    interface = detect_vpn_interface()

    if interface:
        result['interface'] = interface
        result['active'] = True

        # Get interface statistics
        try:
            if shutil.which('ip'):
                proc = subprocess.run(
                    ['ip', '-s', 'link', 'show', interface],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                if proc.returncode == 0:
                    lines = proc.stdout.split('\n')
                    for i, line in enumerate(lines):
                        if 'RX:' in line and i + 1 < len(lines):
                            stats_line = lines[i + 1].strip().split()
                            if stats_line:
                                result['rx_bytes'] = int(stats_line[0])
                        if 'TX:' in line and i + 1 < len(lines):
                            stats_line = lines[i + 1].strip().split()
                            if stats_line:
                                result['tx_bytes'] = int(stats_line[0])
            elif shutil.which('ifconfig'):
                proc = subprocess.run(
                    ['ifconfig', interface],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if proc.returncode == 0:
                    for line in proc.stdout.split('\n'):
                        line = line.strip()
                        if line.lower().startswith('rx bytes'):
                            parts = line.replace(':', ' ').split()
                            if len(parts) >= 3:
                                result['rx_bytes'] = int(parts[2])
                        if line.lower().startswith('tx bytes'):
                            parts = line.replace(':', ' ').split()
                            if len(parts) >= 3:
                                result['tx_bytes'] = int(parts[2])
        except Exception:
            pass

    return result


def check_connectivity(target: str = '1.1.1.1', timeout: int = 2) -> Dict[str, Any]:
    """
    Quick connectivity check via ping.
    """
    result = {
        'target': target,
        'reachable': False,
        'latency_ms': 0,
        'timestamp': time.time()
    }

    try:
        proc = subprocess.run(
            ['ping', '-c', '1', '-W', str(timeout), target],
            capture_output=True,
            text=True,
            timeout=timeout + 1
        )

        if proc.returncode == 0:
            result['reachable'] = True
            # Extract latency
            if 'time=' in proc.stdout:
                time_part = proc.stdout.split('time=')[1].split()[0]
                result['latency_ms'] = float(time_part.replace('ms', ''))
    except Exception:
        pass

    return result


def run_stability_test(
    duration_seconds: int = 30,
    check_interval: int = 2,
    connectivity_target: str = '1.1.1.1'
) -> StabilityTestResult:
    """
    Run tunnel stability monitoring test.

    Args:
        duration_seconds: How long to monitor
        check_interval: Seconds between checks
        connectivity_target: IP to ping for connectivity checks

    Returns:
        StabilityTestResult with stability metrics
    """
    start_time = time.time()
    timestamp = start_time

    # Initial VPN check
    vpn_interface = detect_vpn_interface()
    vpn_detected = vpn_interface is not None

    connectivity_checks = []
    interface_changes = []

    tunnel_drops = 0
    reconnections = 0
    reconnect_times = []

    last_interface = vpn_interface
    last_status_active = vpn_detected
    drop_start_time = None

    checks_performed = 0
    connected_checks = 0

    # Monitor loop
    end_time = start_time + duration_seconds

    while time.time() < end_time:
        check_start = time.time()

        # Check VPN status
        vpn_status = check_vpn_status()
        current_interface = vpn_status['interface']
        current_active = vpn_status['active']

        # Check connectivity
        conn_check = check_connectivity(connectivity_target)
        connectivity_checks.append(conn_check)
        checks_performed += 1

        if conn_check['reachable']:
            connected_checks += 1

        # Detect interface changes
        if current_interface != last_interface:
            interface_changes.append({
                'timestamp': time.time(),
                'from_interface': last_interface,
                'to_interface': current_interface,
                'type': 'interface_change'
            })

        # Detect tunnel drops and reconnections
        if last_status_active and not current_active:
            # Tunnel dropped
            tunnel_drops += 1
            drop_start_time = time.time()
            interface_changes.append({
                'timestamp': time.time(),
                'from_interface': last_interface,
                'to_interface': None,
                'type': 'tunnel_drop'
            })

        elif not last_status_active and current_active:
            # Tunnel reconnected
            reconnections += 1
            if drop_start_time:
                reconnect_time = time.time() - drop_start_time
                reconnect_times.append(reconnect_time)
                drop_start_time = None
            interface_changes.append({
                'timestamp': time.time(),
                'from_interface': None,
                'to_interface': current_interface,
                'type': 'tunnel_reconnect'
            })

        last_interface = current_interface
        last_status_active = current_active

        # Wait for next check
        elapsed = time.time() - check_start
        sleep_time = max(0, check_interval - elapsed)
        if sleep_time > 0 and time.time() + sleep_time < end_time:
            time.sleep(sleep_time)

    # Calculate metrics
    actual_duration = time.time() - start_time

    if checks_performed > 0:
        uptime_percent = (connected_checks / checks_performed) * 100
    else:
        uptime_percent = 0

    if reconnect_times:
        avg_reconnect = sum(reconnect_times) / len(reconnect_times)
        max_reconnect = max(reconnect_times)
    else:
        avg_reconnect = 0
        max_reconnect = 0

    # Determine stability rating
    if not vpn_detected:
        stability_rating = 'unknown'
    elif tunnel_drops == 0 and uptime_percent >= 99:
        stability_rating = 'excellent'
    elif tunnel_drops <= 1 and uptime_percent >= 95:
        stability_rating = 'good'
    elif tunnel_drops <= 2 and uptime_percent >= 90:
        stability_rating = 'acceptable'
    elif tunnel_drops <= 3 and uptime_percent >= 80:
        stability_rating = 'poor'
    else:
        stability_rating = 'unstable'

    return StabilityTestResult(
        vpn_interface=vpn_interface,
        vpn_detected=vpn_detected,
        test_duration_seconds=round(actual_duration, 2),
        checks_performed=checks_performed,
        tunnel_drops=tunnel_drops,
        reconnections=reconnections,
        avg_reconnect_time_seconds=round(avg_reconnect, 2),
        max_reconnect_time_seconds=round(max_reconnect, 2),
        uptime_percent=round(uptime_percent, 2),
        connectivity_checks=connectivity_checks,
        interface_changes=interface_changes,
        timestamp=timestamp,
        stability_rating=stability_rating
    )


if __name__ == '__main__':
    print("Running tunnel stability test...")
    print("Monitoring VPN tunnel for 30 seconds...\n")

    result = run_stability_test(duration_seconds=30)

    print(f"Stability Test Results:")
    print(f"  VPN Detected:        {result.vpn_detected}")
    if result.vpn_interface:
        print(f"  VPN Interface:       {result.vpn_interface}")
    print(f"  Test Duration:       {result.test_duration_seconds:.1f}s")
    print(f"  Checks Performed:    {result.checks_performed}")
    print(f"  Tunnel Drops:        {result.tunnel_drops}")
    print(f"  Reconnections:       {result.reconnections}")
    if result.avg_reconnect_time_seconds > 0:
        print(f"  Avg Reconnect Time:  {result.avg_reconnect_time_seconds:.1f}s")
    print(f"  Uptime:              {result.uptime_percent:.1f}%")
    print(f"  Stability Rating:    {result.stability_rating}")
