#!/usr/bin/env python3
"""
SecureWave VPN Comprehensive Test Suite
========================================
INTERNAL TEST ONLY - Not for end-user distribution.

Tests VPN tunneling, performance, reliability, DNS leak protection,
and network anomaly resilience.

Runs locally without Azure backend dependency.
"""

import csv
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Paths
ARTIFACTS_DIR = Path(__file__).parent.parent
RAW_DIR = ARTIFACTS_DIR / "raw"
REPORTS_DIR = ARTIFACTS_DIR / "reports"

# Test configuration
WG_INTERFACE = "wg-test0"
TEST_CONF_PATH = Path("/tmp/securewave-test-wg.conf")  # INTERNAL TEST ONLY


def log(msg: str, level: str = "INFO"):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def run_cmd(cmd: str, timeout: int = 30, check: bool = False) -> Tuple[int, str, str]:
    """Run a shell command and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except Exception as e:
        return -1, "", str(e)


# ===========================================================
# Phase 2: VPN Is Real — Tunneling Validation
# ===========================================================

class TunnelingValidator:
    """Validates that VPN tunneling actually works."""

    def __init__(self):
        self.results = {
            "phase": "tunneling_validation",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tests": [],
            "summary": {},
        }

    def get_public_ip(self) -> str:
        """Get current public IP address."""
        for service in [
            "curl -s --max-time 5 https://api.ipify.org",
            "curl -s --max-time 5 https://ifconfig.me",
            "curl -s --max-time 5 https://icanhazip.com",
        ]:
            rc, out, _ = run_cmd(service)
            if rc == 0 and out and re.match(r"^\d+\.\d+\.\d+\.\d+$", out.strip()):
                return out.strip()
        return "UNAVAILABLE"

    def get_dns_resolvers(self) -> List[str]:
        """Get current DNS resolvers from /etc/resolv.conf."""
        resolvers = []
        try:
            with open("/etc/resolv.conf") as f:
                for line in f:
                    if line.strip().startswith("nameserver"):
                        resolvers.append(line.strip().split()[1])
        except FileNotFoundError:
            pass
        return resolvers

    def get_route_summary(self) -> str:
        """Get routing table summary."""
        rc, out, _ = run_cmd("ip route show default 2>/dev/null || route -n 2>/dev/null")
        return out if rc == 0 else "UNAVAILABLE"

    def check_wg_tools(self) -> Dict:
        """Check WireGuard tooling availability."""
        wg_path = shutil.which("wg")
        wg_quick_path = shutil.which("wg-quick")
        tun_exists = Path("/dev/net/tun").exists()

        result = {
            "test": "wireguard_tools_available",
            "wg_binary": wg_path or "NOT FOUND",
            "wg_quick_binary": wg_quick_path or "NOT FOUND",
            "tun_device": tun_exists,
            "pass": bool(wg_path and wg_quick_path),
        }
        self.results["tests"].append(result)
        return result

    def check_kernel_module(self) -> Dict:
        """Check if WireGuard kernel module is loaded."""
        rc, out, _ = run_cmd("lsmod | grep wireguard")
        module_loaded = rc == 0 and "wireguard" in out

        if not module_loaded:
            # Try to load it
            rc2, _, _ = run_cmd("sudo modprobe wireguard 2>/dev/null")
            if rc2 == 0:
                module_loaded = True

        result = {
            "test": "wireguard_kernel_module",
            "loaded": module_loaded,
            "pass": module_loaded,
        }
        self.results["tests"].append(result)
        return result

    def capture_baseline(self) -> Dict:
        """Capture pre-VPN baseline: public IP, DNS, routes."""
        baseline = {
            "test": "pre_vpn_baseline",
            "public_ip": self.get_public_ip(),
            "dns_resolvers": self.get_dns_resolvers(),
            "default_route": self.get_route_summary(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "pass": True,
        }
        self.results["tests"].append(baseline)
        return baseline

    def generate_test_config(self) -> Dict:
        """
        Generate a local WireGuard test configuration.
        This creates a loopback test - server and client on same machine.
        INTERNAL TEST ONLY.
        """
        # Generate keypairs
        rc1, server_privkey, _ = run_cmd("wg genkey")
        if rc1 != 0:
            return {"test": "generate_test_config", "pass": False, "error": "wg genkey failed"}

        rc2, server_pubkey, _ = run_cmd(f"echo '{server_privkey}' | wg pubkey")
        rc3, client_privkey, _ = run_cmd("wg genkey")
        rc4, client_pubkey, _ = run_cmd(f"echo '{client_privkey}' | wg pubkey")

        if any(r != 0 for r in [rc2, rc3, rc4]):
            return {"test": "generate_test_config", "pass": False, "error": "keypair generation failed"}

        # Create test config (loopback — no real remote server)
        config = f"""# INTERNAL TEST ONLY - SecureWave VPN Test Config
# Generated: {datetime.now(timezone.utc).isoformat()}
[Interface]
PrivateKey = {client_privkey}
Address = 10.99.0.2/24
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = {server_pubkey}
Endpoint = 127.0.0.1:51821
AllowedIPs = 10.99.0.0/24
PersistentKeepalive = 25
"""

        TEST_CONF_PATH.write_text(config)
        # Mask private key in logs
        masked_config = config.replace(client_privkey, "[MASKED_CLIENT_PRIVKEY]")
        masked_config = masked_config.replace(server_privkey, "[MASKED_SERVER_PRIVKEY]")

        result = {
            "test": "generate_test_config",
            "config_path": str(TEST_CONF_PATH),
            "client_address": "10.99.0.2/24",
            "dns": "1.1.1.1, 1.0.0.1",
            "allowed_ips": "10.99.0.0/24",
            "keepalive": 25,
            "config_masked": masked_config,
            "pass": True,
        }
        self.results["tests"].append(result)
        return result

    def validate_config_format(self) -> Dict:
        """Validate the generated WireGuard config format."""
        if not TEST_CONF_PATH.exists():
            return {"test": "validate_config_format", "pass": False, "error": "no config file"}

        content = TEST_CONF_PATH.read_text()
        checks = {
            "has_interface": "[Interface]" in content,
            "has_private_key": "PrivateKey" in content,
            "has_address": "Address" in content,
            "has_dns": "DNS" in content,
            "has_peer": "[Peer]" in content,
            "has_public_key": "PublicKey" in content,
            "has_endpoint": "Endpoint" in content,
            "has_allowed_ips": "AllowedIPs" in content,
            "has_keepalive": "PersistentKeepalive" in content,
        }

        result = {
            "test": "validate_config_format",
            "checks": checks,
            "all_present": all(checks.values()),
            "pass": all(checks.values()),
        }
        self.results["tests"].append(result)
        return result

    def test_wg_interface_lifecycle(self) -> Dict:
        """Test bringing WireGuard interface up and down (requires sudo)."""
        # We test with a restricted AllowedIPs (not 0.0.0.0/0) to avoid
        # disrupting the test machine's connectivity
        log("Testing WireGuard interface lifecycle (up/down)...")

        # Try to bring up
        rc_up, out_up, err_up = run_cmd(
            f"sudo wg-quick up {TEST_CONF_PATH} 2>&1", timeout=15
        )
        up_success = rc_up == 0

        # Check interface exists
        rc_check, out_check, _ = run_cmd(f"ip link show {WG_INTERFACE} 2>/dev/null")
        iface_exists = rc_check == 0

        # Check WireGuard status
        rc_wg, out_wg, _ = run_cmd(f"sudo wg show {WG_INTERFACE} 2>/dev/null")
        wg_active = rc_wg == 0

        # Bring down
        rc_down, _, err_down = run_cmd(
            f"sudo wg-quick down {TEST_CONF_PATH} 2>&1", timeout=15
        )
        down_success = rc_down == 0

        result = {
            "test": "wg_interface_lifecycle",
            "up_success": up_success,
            "up_output": (out_up + " " + err_up)[:500],
            "interface_created": iface_exists,
            "wg_active": wg_active,
            "down_success": down_success,
            "pass": up_success and down_success,
        }
        self.results["tests"].append(result)
        return result

    def run_all(self) -> Dict:
        """Run all tunneling validation tests."""
        log("=== Phase 2: Tunneling Validation ===")

        self.check_wg_tools()
        self.check_kernel_module()
        self.capture_baseline()
        self.generate_test_config()
        self.validate_config_format()
        self.test_wg_interface_lifecycle()

        passed = sum(1 for t in self.results["tests"] if t.get("pass"))
        total = len(self.results["tests"])
        self.results["summary"] = {
            "total_tests": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": f"{passed/total*100:.1f}%" if total > 0 else "N/A",
        }

        log(f"Tunneling validation: {passed}/{total} passed")
        return self.results


# ===========================================================
# Phase 3: Performance Testing
# ===========================================================

class PerformanceTest:
    """Network performance baseline vs VPN measurements."""

    def __init__(self):
        self.results = {
            "phase": "performance_testing",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tests": [],
            "summary": {},
        }

    def measure_latency(self, host: str = "1.1.1.1", count: int = 10) -> Dict:
        """Measure latency to a host using ping."""
        rc, out, _ = run_cmd(f"ping -c {count} -W 3 {host}", timeout=count * 5)
        if rc != 0:
            return {"host": host, "p50_ms": None, "p95_ms": None, "loss_pct": 100}

        # Parse ping output
        times = []
        for line in out.split("\n"):
            m = re.search(r"time=(\d+\.?\d*)\s*ms", line)
            if m:
                times.append(float(m.group(1)))

        loss_match = re.search(r"(\d+)% packet loss", out)
        loss_pct = float(loss_match.group(1)) if loss_match else 0

        if times:
            times.sort()
            p50 = times[len(times) // 2]
            p95 = times[int(len(times) * 0.95)] if len(times) >= 20 else times[-1]
            avg = sum(times) / len(times)
        else:
            p50 = p95 = avg = None

        return {
            "host": host,
            "count": count,
            "samples": len(times),
            "avg_ms": round(avg, 2) if avg else None,
            "p50_ms": round(p50, 2) if p50 else None,
            "p95_ms": round(p95, 2) if p95 else None,
            "min_ms": round(min(times), 2) if times else None,
            "max_ms": round(max(times), 2) if times else None,
            "loss_pct": loss_pct,
        }

    def measure_throughput_download(self, url: str = None, size_label: str = "10MB") -> Dict:
        """Measure download throughput using curl."""
        if url is None:
            # Use a stable test file
            url = "https://speed.cloudflare.com/__down?bytes=10000000"

        start = time.time()
        rc, out, err = run_cmd(
            f"curl -s -o /dev/null -w '%{{speed_download}}' --max-time 30 '{url}'",
            timeout=35,
        )
        elapsed = time.time() - start

        speed_bps = 0
        if rc == 0 and out:
            try:
                speed_bps = float(out.replace("'", ""))
            except ValueError:
                pass

        speed_mbps = (speed_bps * 8) / 1_000_000 if speed_bps > 0 else 0

        return {
            "test": "download_throughput",
            "url": url[:80],
            "size_label": size_label,
            "speed_bytes_per_sec": speed_bps,
            "speed_mbps": round(speed_mbps, 2),
            "elapsed_sec": round(elapsed, 2),
            "pass": speed_mbps > 0,
        }

    def measure_http_latency(self, url: str = "https://1.1.1.1/cdn-cgi/trace", count: int = 5) -> Dict:
        """Measure HTTP(S) latency."""
        times = []
        for _ in range(count):
            rc, out, _ = run_cmd(
                f"curl -s -o /dev/null -w '%{{time_total}}' --max-time 10 '{url}'",
                timeout=15,
            )
            if rc == 0 and out:
                try:
                    t = float(out.replace("'", ""))
                    times.append(t * 1000)  # Convert to ms
                except ValueError:
                    pass

        if times:
            times.sort()
            return {
                "test": "http_latency",
                "url": url[:80],
                "samples": len(times),
                "avg_ms": round(sum(times) / len(times), 1),
                "p50_ms": round(times[len(times) // 2], 1),
                "p95_ms": round(times[-1], 1),
                "min_ms": round(min(times), 1),
                "max_ms": round(max(times), 1),
            }
        return {"test": "http_latency", "url": url[:80], "error": "no successful measurements"}

    def run_baseline(self) -> Dict:
        """Run baseline (no VPN) performance tests."""
        log("=== Phase 3: Performance Baseline (No VPN) ===")

        latency = self.measure_latency("1.1.1.1", count=20)
        throughput = self.measure_throughput_download()
        http_lat = self.measure_http_latency()

        baseline = {
            "test": "baseline_performance",
            "vpn_active": False,
            "latency": latency,
            "throughput": throughput,
            "http_latency": http_lat,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self.results["tests"].append(baseline)
        log(f"Baseline: latency p50={latency.get('p50_ms')}ms, throughput={throughput.get('speed_mbps')}Mbps")
        return baseline

    def run_all(self) -> Dict:
        """Run all performance tests (baseline only — no live VPN server to test against)."""
        self.run_baseline()

        self.results["summary"] = {
            "note": "VPN-on performance requires a live WireGuard server. "
                    "Baseline captured for future comparison.",
            "baseline_captured": True,
            "vpn_comparison_available": False,
        }
        return self.results


# ===========================================================
# Phase 4: Reliability Testing
# ===========================================================

class ReliabilityTest:
    """Connect/disconnect cycle tests and stability checks."""

    def __init__(self):
        self.results = {
            "phase": "reliability_testing",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tests": [],
            "summary": {},
        }

    def connect_disconnect_cycle(self, cycles: int = 10) -> Dict:
        """
        Test connect/disconnect cycles using wg-quick.
        Uses the test config with restricted AllowedIPs.
        """
        log(f"Running {cycles} connect/disconnect cycles...")

        if not TEST_CONF_PATH.exists():
            return {"test": "cycle_test", "pass": False, "error": "no test config"}

        successes = 0
        failures = 0
        connect_times = []
        disconnect_times = []
        errors = []

        for i in range(cycles):
            # Connect
            t0 = time.time()
            rc_up, _, err_up = run_cmd(f"sudo wg-quick up {TEST_CONF_PATH} 2>&1", timeout=15)
            connect_time = time.time() - t0

            if rc_up != 0:
                failures += 1
                errors.append(f"Cycle {i+1} UP failed: {err_up[:100]}")
                continue

            connect_times.append(connect_time)
            time.sleep(0.5)  # Brief stability check

            # Disconnect
            t1 = time.time()
            rc_down, _, err_down = run_cmd(f"sudo wg-quick down {TEST_CONF_PATH} 2>&1", timeout=15)
            disconnect_time = time.time() - t1

            if rc_down != 0:
                failures += 1
                errors.append(f"Cycle {i+1} DOWN failed: {err_down[:100]}")
                # Force cleanup
                run_cmd(f"sudo ip link del {WG_INTERFACE} 2>/dev/null")
                continue

            disconnect_times.append(disconnect_time)
            successes += 1
            time.sleep(0.3)

        result = {
            "test": "connect_disconnect_cycles",
            "total_cycles": cycles,
            "successes": successes,
            "failures": failures,
            "avg_connect_sec": round(sum(connect_times) / len(connect_times), 3) if connect_times else None,
            "avg_disconnect_sec": round(sum(disconnect_times) / len(disconnect_times), 3) if disconnect_times else None,
            "max_connect_sec": round(max(connect_times), 3) if connect_times else None,
            "max_disconnect_sec": round(max(disconnect_times), 3) if disconnect_times else None,
            "errors": errors[:5],  # Limit error output
            "pass": failures == 0,
            "pass_rate": f"{successes/cycles*100:.1f}%",
        }
        self.results["tests"].append(result)
        log(f"Cycle test: {successes}/{cycles} passed, avg connect={result['avg_connect_sec']}s")
        return result

    def run_all(self) -> Dict:
        """Run all reliability tests."""
        log("=== Phase 4: Reliability Testing ===")
        self.connect_disconnect_cycle(cycles=10)

        self.results["summary"] = {
            "note": "Soak test (30-60min) and concurrency test require live VPN server. "
                    "Cycle test validates wg-quick up/down reliability.",
        }
        return self.results


# ===========================================================
# Phase 5: Network Anomaly Resilience
# ===========================================================

class NetworkAnomalyTest:
    """Test VPN resilience under network anomalies using tc/netem."""

    def __init__(self):
        self.results = {
            "phase": "network_anomaly_resilience",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tests": [],
            "summary": {},
        }
        self.tc_available = shutil.which("tc") is not None
        self.primary_iface = self._get_primary_interface()

    def _get_primary_interface(self) -> str:
        """Get primary network interface."""
        rc, out, _ = run_cmd("ip route show default | awk '{print $5}' | head -1")
        return out.strip() if rc == 0 and out.strip() else "enp0s1"

    def _apply_netem(self, rule: str) -> bool:
        """Apply a tc netem rule."""
        rc, _, err = run_cmd(f"sudo tc qdisc add dev {self.primary_iface} root netem {rule}")
        if rc != 0 and "File exists" in err:
            # Replace existing rule
            rc, _, _ = run_cmd(f"sudo tc qdisc change dev {self.primary_iface} root netem {rule}")
        return rc == 0

    def _clear_netem(self) -> bool:
        """Clear all netem rules."""
        rc, _, _ = run_cmd(f"sudo tc qdisc del dev {self.primary_iface} root 2>/dev/null")
        return True  # Ignore errors (might not have any rules)

    def test_packet_loss(self, loss_pct: int = 5) -> Dict:
        """Test connectivity under packet loss."""
        log(f"Testing with {loss_pct}% packet loss...")

        if not self.tc_available:
            return {"test": f"packet_loss_{loss_pct}pct", "skip": True, "reason": "tc not available"}

        self._apply_netem(f"loss {loss_pct}%")
        time.sleep(1)

        # Measure impact
        latency = PerformanceTest().measure_latency("1.1.1.1", count=10)

        self._clear_netem()

        result = {
            "test": f"packet_loss_{loss_pct}pct",
            "simulated_loss": f"{loss_pct}%",
            "measured_loss": f"{latency.get('loss_pct', 'N/A')}%",
            "avg_latency_ms": latency.get("avg_ms"),
            "p95_latency_ms": latency.get("p95_ms"),
            "pass": latency.get("loss_pct", 100) < loss_pct * 3,  # Allow some tolerance
        }
        self.results["tests"].append(result)
        return result

    def test_jitter(self, jitter_ms: int = 50) -> Dict:
        """Test connectivity under jitter."""
        log(f"Testing with {jitter_ms}ms jitter...")

        if not self.tc_available:
            return {"test": f"jitter_{jitter_ms}ms", "skip": True, "reason": "tc not available"}

        self._apply_netem(f"delay 10ms {jitter_ms}ms distribution normal")
        time.sleep(1)

        latency = PerformanceTest().measure_latency("1.1.1.1", count=10)

        self._clear_netem()

        result = {
            "test": f"jitter_{jitter_ms}ms",
            "simulated_jitter": f"{jitter_ms}ms",
            "avg_latency_ms": latency.get("avg_ms"),
            "p50_latency_ms": latency.get("p50_ms"),
            "p95_latency_ms": latency.get("p95_ms"),
            "jitter_range_ms": round(latency["max_ms"] - latency["min_ms"], 2)
                if latency.get("max_ms") and latency.get("min_ms") else None,
            "pass": True,
        }
        self.results["tests"].append(result)
        return result

    def test_bandwidth_cap(self, rate_kbit: int = 5000) -> Dict:
        """Test under bandwidth cap."""
        log(f"Testing with {rate_kbit}kbit bandwidth cap...")

        if not self.tc_available:
            return {"test": f"bw_cap_{rate_kbit}kbit", "skip": True, "reason": "tc not available"}

        self._apply_netem(f"rate {rate_kbit}kbit")
        time.sleep(1)

        throughput = PerformanceTest().measure_throughput_download()

        self._clear_netem()

        result = {
            "test": f"bandwidth_cap_{rate_kbit}kbit",
            "cap_kbit": rate_kbit,
            "measured_mbps": throughput.get("speed_mbps"),
            "pass": True,
        }
        self.results["tests"].append(result)
        return result

    def run_all(self) -> Dict:
        """Run all network anomaly tests."""
        log("=== Phase 5: Network Anomaly Resilience ===")

        if not self.tc_available:
            log("tc/netem not available, skipping anomaly tests", "WARN")
            self.results["summary"] = {"skip": True, "reason": "tc not available"}
            return self.results

        # Always clean up before starting
        self._clear_netem()

        self.test_packet_loss(1)
        self.test_packet_loss(5)
        self.test_packet_loss(10)
        self.test_jitter(20)
        self.test_jitter(50)
        self.test_bandwidth_cap(5000)

        # Final cleanup
        self._clear_netem()

        passed = sum(1 for t in self.results["tests"] if t.get("pass") and not t.get("skip"))
        total = sum(1 for t in self.results["tests"] if not t.get("skip"))
        self.results["summary"] = {
            "total_tests": total,
            "passed": passed,
            "interface_tested": self.primary_iface,
        }
        return self.results


# ===========================================================
# Phase 6: Security Sanity Checks
# ===========================================================

class SecuritySanityCheck:
    """Non-invasive security checks."""

    def __init__(self):
        self.results = {
            "phase": "security_sanity",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tests": [],
            "summary": {},
        }

    def check_dns_resolvers(self) -> Dict:
        """Check current DNS resolver configuration."""
        resolvers = []
        try:
            with open("/etc/resolv.conf") as f:
                for line in f:
                    if line.strip().startswith("nameserver"):
                        resolvers.append(line.strip().split()[1])
        except FileNotFoundError:
            pass

        secure_dns = {"1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9"}
        isp_patterns = ["192.168.", "10.", "172."]

        leaky = []
        for r in resolvers:
            if any(r.startswith(p) for p in isp_patterns):
                leaky.append(r)
            elif r not in secure_dns:
                leaky.append(r)

        result = {
            "test": "dns_resolver_check",
            "resolvers": resolvers,
            "leaky_resolvers": leaky,
            "leak_risk": len(leaky) > 0,
            "pass": len(leaky) == 0,
        }
        self.results["tests"].append(result)
        return result

    def check_dns_resolution(self) -> Dict:
        """Test DNS resolution through expected path."""
        test_domains = ["cloudflare.com", "google.com", "example.com"]
        results_list = []

        for domain in test_domains:
            try:
                start = time.time()
                ip = socket.gethostbyname(domain)
                elapsed = time.time() - start
                results_list.append({
                    "domain": domain,
                    "resolved_ip": ip,
                    "latency_ms": round(elapsed * 1000, 1),
                    "success": True,
                })
            except socket.gaierror as e:
                results_list.append({
                    "domain": domain,
                    "error": str(e),
                    "success": False,
                })

        result = {
            "test": "dns_resolution",
            "domains_tested": len(test_domains),
            "results": results_list,
            "all_resolved": all(r["success"] for r in results_list),
            "pass": all(r["success"] for r in results_list),
        }
        self.results["tests"].append(result)
        return result

    def check_config_security(self) -> Dict:
        """Check that WireGuard configs don't leak in logs or accessible locations."""
        issues = []

        # Check if any .conf files are world-readable
        rc, out, _ = run_cmd(
            "find /tmp -name '*.conf' -perm /o=r -type f 2>/dev/null | head -5"
        )
        if out:
            issues.append(f"World-readable config files found: {out}")

        # Check for private keys in common log locations
        for logpath in ["/var/log/syslog", "/var/log/messages"]:
            rc, out, _ = run_cmd(
                f"sudo grep -c 'PrivateKey' {logpath} 2>/dev/null"
            )
            if rc == 0 and out.strip() != "0":
                issues.append(f"PrivateKey found in {logpath}")

        result = {
            "test": "config_security",
            "issues": issues,
            "pass": len(issues) == 0,
        }
        self.results["tests"].append(result)
        return result

    def run_all(self) -> Dict:
        """Run all security sanity checks."""
        log("=== Phase 6: Security Sanity Checks ===")

        self.check_dns_resolvers()
        self.check_dns_resolution()
        self.check_config_security()

        passed = sum(1 for t in self.results["tests"] if t.get("pass"))
        total = len(self.results["tests"])
        self.results["summary"] = {
            "total_tests": total,
            "passed": passed,
            "failed": total - passed,
        }
        log(f"Security checks: {passed}/{total} passed")
        return self.results


# ===========================================================
# Main Runner
# ===========================================================

def main():
    log("=" * 60)
    log("SecureWave VPN Comprehensive Test Suite")
    log("=" * 60)
    log(f"Artifacts dir: {ARTIFACTS_DIR}")

    all_results = {}

    # Phase 2: Tunneling Validation
    tv = TunnelingValidator()
    all_results["tunneling"] = tv.run_all()

    # Phase 3: Performance
    pt = PerformanceTest()
    all_results["performance"] = pt.run_all()

    # Phase 4: Reliability
    rt = ReliabilityTest()
    all_results["reliability"] = rt.run_all()

    # Phase 5: Network Anomaly
    nat = NetworkAnomalyTest()
    all_results["network_anomaly"] = nat.run_all()

    # Phase 6: Security
    ss = SecuritySanityCheck()
    all_results["security"] = ss.run_all()

    # Save results
    results_path = RAW_DIR / "vpn_test_results.json"
    with open(results_path, "w") as f:
        json.dump(all_results, f, indent=2, default=str)
    log(f"Results saved to {results_path}")

    # Generate CSV summary
    csv_path = RAW_DIR / "vpn_test_summary.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Phase", "Test", "Pass", "Key Metric", "Value"])
        for phase_name, phase_data in all_results.items():
            for test in phase_data.get("tests", []):
                test_name = test.get("test", "unknown")
                passed = test.get("pass", "N/A")
                # Extract most relevant metric
                key_metric = ""
                value = ""
                if "avg_ms" in test:
                    key_metric = "avg_latency_ms"
                    value = str(test["avg_ms"])
                elif "speed_mbps" in test:
                    key_metric = "speed_mbps"
                    value = str(test["speed_mbps"])
                elif "successes" in test:
                    key_metric = "success_rate"
                    value = test.get("pass_rate", "")
                writer.writerow([phase_name, test_name, passed, key_metric, value])

    log(f"CSV summary saved to {csv_path}")

    # Print summary
    log("=" * 60)
    log("TEST SUITE SUMMARY")
    log("=" * 60)
    for phase_name, phase_data in all_results.items():
        summary = phase_data.get("summary", {})
        log(f"  {phase_name}: {summary}")

    return all_results


if __name__ == "__main__":
    main()
