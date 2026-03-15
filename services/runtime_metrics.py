"""
In-process runtime metrics for observability endpoints.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from statistics import mean
from typing import Deque, Dict, Iterable, List, Optional

import psutil


def _percentile(values: List[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return float(ordered[f] + (k - f) * (ordered[c] - ordered[f]))


class RuntimeMetrics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._started_at = time.time()
        self._vpn_profiles_issued_total = 0
        self._vpn_profiles_failed_total = 0
        self._peer_connect_total = 0
        self._peer_disconnect_total = 0
        self._auth_failed_total = 0
        self._rate_limited_total = 0
        self._region_resolution_total = 0
        self._region_failover_total = 0
        self._region_circuit_open_total = 0
        self._profile_issue_latencies_ms: Deque[float] = deque(maxlen=10_000)
        self._handshake_latencies_ms: Deque[float] = deque(maxlen=10_000)
        self._extended_system_cache: Dict[str, float] = {}
        self._extended_system_cache_at = 0.0

    def record_profile_issue(self, *, latency_ms: float, success: bool = True) -> None:
        with self._lock:
            self._vpn_profiles_issued_total += 1
            if not success:
                self._vpn_profiles_failed_total += 1
            if latency_ms >= 0:
                self._profile_issue_latencies_ms.append(float(latency_ms))

    def record_peer_connect(self) -> None:
        with self._lock:
            self._peer_connect_total += 1

    def record_peer_disconnect(self) -> None:
        with self._lock:
            self._peer_disconnect_total += 1

    def record_failed_auth(self) -> None:
        with self._lock:
            self._auth_failed_total += 1

    def record_rate_limited(self) -> None:
        with self._lock:
            self._rate_limited_total += 1

    def record_handshake_latency(self, latency_ms: float) -> None:
        with self._lock:
            if latency_ms >= 0:
                self._handshake_latencies_ms.append(float(latency_ms))

    def record_region_resolution(self, *, reason: Optional[str] = None) -> None:
        normalized = (reason or "").strip().lower()
        with self._lock:
            self._region_resolution_total += 1
            if any(token in normalized for token in ("fallback", "failover", "region_down", "barbados_eu")):
                self._region_failover_total += 1

    def record_region_circuit_open(self) -> None:
        with self._lock:
            self._region_circuit_open_total += 1

    def _latency_stats(self, values: Iterable[float]) -> Dict[str, float]:
        data = list(values)
        if not data:
            return {
                "count": 0,
                "avg_ms": 0.0,
                "p50_ms": 0.0,
                "p95_ms": 0.0,
                "max_ms": 0.0,
            }
        return {
            "count": len(data),
            "avg_ms": round(mean(data), 2),
            "p50_ms": round(_percentile(data, 50), 2),
            "p95_ms": round(_percentile(data, 95), 2),
            "max_ms": round(max(data), 2),
        }

    def snapshot(self) -> Dict:
        with self._lock:
            profile_latencies = list(self._profile_issue_latencies_ms)
            handshake_latencies = list(self._handshake_latencies_ms)
            counters = {
                "vpn_profiles_issued_total": self._vpn_profiles_issued_total,
                "vpn_profiles_failed_total": self._vpn_profiles_failed_total,
                "peer_connect_total": self._peer_connect_total,
                "peer_disconnect_total": self._peer_disconnect_total,
                "auth_failed_total": self._auth_failed_total,
                "rate_limited_total": self._rate_limited_total,
                "region_resolution_total": self._region_resolution_total,
                "region_failover_total": self._region_failover_total,
                "region_circuit_open_total": self._region_circuit_open_total,
            }

        vm = psutil.virtual_memory()
        cpu_percent = psutil.cpu_percent(interval=0.0)
        proc = psutil.Process()
        process_memory_mb = proc.memory_info().rss / 1024 / 1024

        extended = self._extended_system_snapshot(proc)

        return {
            "uptime_seconds": round(time.time() - self._started_at, 2),
            "counters": counters,
            "profile_issue_latency": self._latency_stats(profile_latencies),
            "handshake_latency": self._latency_stats(handshake_latencies),
            "system": {
                "cpu_percent": round(cpu_percent, 2),
                "memory_percent": round(vm.percent, 2),
                "process_memory_mb": round(process_memory_mb, 2),
                **extended,
            },
        }

    def _extended_system_snapshot(self, proc: psutil.Process) -> Dict[str, float]:
        """
        Compute additional system/process metrics with lightweight caching.

        This keeps Prometheus scrapes cheap while still surfacing FD/thread
        growth and stray wg processes.
        """
        now = time.time()
        with self._lock:
            if now - self._extended_system_cache_at < 10.0 and self._extended_system_cache:
                return dict(self._extended_system_cache)

        open_fds: Optional[int] = None
        try:
            open_fds = int(proc.num_fds())
        except Exception:
            open_fds = None

        try:
            threads = int(proc.num_threads())
        except Exception:
            threads = 0

        wg_processes = 0
        zombie_processes = 0
        try:
            for p in psutil.process_iter(attrs=["name", "cmdline", "status"]):
                info = p.info or {}
                name = (info.get("name") or "").lower()
                cmdline = " ".join(info.get("cmdline") or []).lower()
                status = (info.get("status") or "").lower()

                if status == psutil.STATUS_ZOMBIE or status == "zombie":
                    zombie_processes += 1

                if name in {"wg", "wg-quick", "wireguard-go"}:
                    wg_processes += 1
                    continue
                if "wg-quick" in cmdline or cmdline.startswith("wg "):
                    wg_processes += 1
        except Exception:
            # Best-effort only; never fail metrics endpoints.
            pass

        extended = {
            "process_open_fds": float(open_fds) if open_fds is not None else -1.0,
            "process_threads": float(threads),
            "wg_processes": float(wg_processes),
            "zombie_processes": float(zombie_processes),
        }

        with self._lock:
            self._extended_system_cache = dict(extended)
            self._extended_system_cache_at = now
        return extended

    def export_prometheus(self, *, fleet: Optional[Dict] = None) -> str:
        snapshot = self.snapshot()
        counters = snapshot["counters"]
        profile_latency = snapshot["profile_issue_latency"]
        handshake_latency = snapshot["handshake_latency"]
        system = snapshot["system"]

        lines = [
            "# HELP securewave_vpn_profiles_issued_total Total VPN profile issuance attempts.",
            "# TYPE securewave_vpn_profiles_issued_total counter",
            f"securewave_vpn_profiles_issued_total {counters['vpn_profiles_issued_total']}",
            "# HELP securewave_vpn_profiles_failed_total Total failed VPN profile issuances.",
            "# TYPE securewave_vpn_profiles_failed_total counter",
            f"securewave_vpn_profiles_failed_total {counters['vpn_profiles_failed_total']}",
            "# HELP securewave_peer_connect_total Total peer connect events.",
            "# TYPE securewave_peer_connect_total counter",
            f"securewave_peer_connect_total {counters['peer_connect_total']}",
            "# HELP securewave_peer_disconnect_total Total peer disconnect events.",
            "# TYPE securewave_peer_disconnect_total counter",
            f"securewave_peer_disconnect_total {counters['peer_disconnect_total']}",
            "# HELP securewave_auth_failed_total Total failed authentication attempts.",
            "# TYPE securewave_auth_failed_total counter",
            f"securewave_auth_failed_total {counters['auth_failed_total']}",
            "# HELP securewave_region_resolution_total Total region resolution decisions.",
            "# TYPE securewave_region_resolution_total counter",
            f"securewave_region_resolution_total {counters['region_resolution_total']}",
            "# HELP securewave_region_failover_total Total region resolutions that used fallback/failover paths.",
            "# TYPE securewave_region_failover_total counter",
            f"securewave_region_failover_total {counters['region_failover_total']}",
            "# HELP securewave_region_circuit_open_total Total times region probe circuits opened.",
            "# TYPE securewave_region_circuit_open_total counter",
            f"securewave_region_circuit_open_total {counters['region_circuit_open_total']}",
            "# HELP securewave_profile_issue_latency_p95_ms P95 VPN profile issue latency (ms).",
            "# TYPE securewave_profile_issue_latency_p95_ms gauge",
            f"securewave_profile_issue_latency_p95_ms {profile_latency['p95_ms']}",
            "# HELP securewave_handshake_latency_p95_ms P95 handshake measurement latency (ms).",
            "# TYPE securewave_handshake_latency_p95_ms gauge",
            f"securewave_handshake_latency_p95_ms {handshake_latency['p95_ms']}",
            "# HELP securewave_system_cpu_percent Host CPU utilization percentage.",
            "# TYPE securewave_system_cpu_percent gauge",
            f"securewave_system_cpu_percent {system['cpu_percent']}",
            "# HELP securewave_system_memory_percent Host memory utilization percentage.",
            "# TYPE securewave_system_memory_percent gauge",
            f"securewave_system_memory_percent {system['memory_percent']}",
            "# HELP securewave_process_memory_mb Process RSS in MB.",
            "# TYPE securewave_process_memory_mb gauge",
            f"securewave_process_memory_mb {system['process_memory_mb']}",
            "# HELP securewave_process_open_fds Process open file descriptors (-1 when unavailable).",
            "# TYPE securewave_process_open_fds gauge",
            f"securewave_process_open_fds {system.get('process_open_fds', -1)}",
            "# HELP securewave_process_threads Process thread count.",
            "# TYPE securewave_process_threads gauge",
            f"securewave_process_threads {system.get('process_threads', 0)}",
            "# HELP securewave_wg_processes Host WireGuard-related process count (best-effort).",
            "# TYPE securewave_wg_processes gauge",
            f"securewave_wg_processes {system.get('wg_processes', 0)}",
            "# HELP securewave_zombie_processes Host zombie process count (best-effort).",
            "# TYPE securewave_zombie_processes gauge",
            f"securewave_zombie_processes {system.get('zombie_processes', 0)}",
        ]

        if fleet:
            lines.extend([
                "# HELP securewave_active_sessions Current active VPN sessions.",
                "# TYPE securewave_active_sessions gauge",
                f"securewave_active_sessions {fleet.get('active_sessions', 0)}",
                "# HELP securewave_active_tunnels Current active WireGuard tunnels.",
                "# TYPE securewave_active_tunnels gauge",
                f"securewave_active_tunnels {fleet.get('active_tunnels', 0)}",
                "# HELP securewave_fleet_total_servers Total active VPN servers.",
                "# TYPE securewave_fleet_total_servers gauge",
                f"securewave_fleet_total_servers {fleet.get('total_servers', 0)}",
                "# HELP securewave_fleet_healthy_servers Healthy VPN servers.",
                "# TYPE securewave_fleet_healthy_servers gauge",
                f"securewave_fleet_healthy_servers {fleet.get('healthy_servers', 0)}",
                "# HELP securewave_fleet_total_connections Total current connections across fleet.",
                "# TYPE securewave_fleet_total_connections gauge",
                f"securewave_fleet_total_connections {fleet.get('total_connections', 0)}",
                "# HELP securewave_fleet_avg_load_score Average server load score (0.0-1.0).",
                "# TYPE securewave_fleet_avg_load_score gauge",
                f"securewave_fleet_avg_load_score {fleet.get('avg_load_score', 0.0)}",
            ])

        return "\n".join(lines) + "\n"


_metrics: RuntimeMetrics | None = None


def get_runtime_metrics() -> RuntimeMetrics:
    global _metrics
    if _metrics is None:
        _metrics = RuntimeMetrics()
    return _metrics
