"""
Geo-aware latency optimizer for server selection.
"""

from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404 - controlled local ping
import time
from dataclasses import dataclass
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class BaselineLatency:
    barbados_ms: float
    frankfurt_ms: float
    source: str  # measured | fallback


@dataclass(frozen=True)
class ScoredServer:
    server_id: str
    score: float
    latency_ms: float


def _default_float(name: str, default: float) -> float:
    raw = os.getenv(name, str(default)).strip()
    try:
        return float(raw)
    except ValueError:
        return default


def _ping_latency_ms(host: str) -> Optional[float]:
    ping = shutil.which("ping")
    if not ping:
        return None

    start = time.monotonic()
    cmd = [ping, "-c", "1", "-W", "1", host]
    try:
        proc = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=2)  # nosec B603
    except (subprocess.SubprocessError, OSError, TimeoutError):
        return None
    if proc.returncode != 0:
        return None

    # Parse avg latency from ping output if available.
    for line in proc.stdout.splitlines():
        if "=" in line and "ms" in line and "/" in line:
            tail = line.split("=", 1)[1].strip().replace(" ms", "")
            parts = tail.split("/")
            if len(parts) >= 2:
                try:
                    return float(parts[1])
                except ValueError:
                    break

    return round((time.monotonic() - start) * 1000, 2)


class GeoLatencyOptimizer:
    def __init__(self) -> None:
        self.barbados_host = os.getenv("BARBADOS_BASELINE_HOST", "1.1.1.1")
        self.frankfurt_host = os.getenv("FRANKFURT_BASELINE_HOST", "8.8.8.8")

    def collect_baselines(self) -> BaselineLatency:
        barbados = _ping_latency_ms(self.barbados_host)
        frankfurt = _ping_latency_ms(self.frankfurt_host)

        if barbados is None or frankfurt is None:
            return BaselineLatency(
                barbados_ms=_default_float("BARBADOS_BASELINE_MS", 95.0),
                frankfurt_ms=_default_float("FRANKFURT_BASELINE_MS", 130.0),
                source="fallback",
            )

        return BaselineLatency(
            barbados_ms=round(barbados, 2),
            frankfurt_ms=round(frankfurt, 2),
            source="measured",
        )

    def score_server(
        self,
        server,
        *,
        baselines: Optional[BaselineLatency] = None,
        user_region_hint: Optional[str] = None,
    ) -> float:
        """
        Score a server using observed RTT + Caribbean/EU corridor weighting.

        Higher score is better.
        """
        baselines = baselines or self.collect_baselines()

        region = (getattr(server, "region", "") or "").lower()
        latency_ms = float(getattr(server, "latency_ms", 999.0) or 999.0)
        performance_score = float(getattr(server, "performance_score", 0.0) or 0.0)

        # Base RTT preference: lower is better.
        rtt_component = max(0.0, 500.0 - latency_ms)

        corridor_multiplier = 1.0
        if region in {"europe", "americas", "caribbean"}:
            corridor_multiplier = 1.25

        # Prefer low RTT corridor between Caribbean and EU by anchoring to both baselines.
        corridor_target = (baselines.barbados_ms + baselines.frankfurt_ms) / 2.0
        corridor_penalty = abs(latency_ms - corridor_target)

        region_hint = (user_region_hint or "").lower()
        if region_hint in {"caribbean", "americas"} and region == "europe":
            corridor_multiplier += 0.1
        if region_hint in {"europe", "eu"} and region in {"americas", "caribbean"}:
            corridor_multiplier += 0.1

        score = (rtt_component * corridor_multiplier) - (0.35 * corridor_penalty) + (0.5 * performance_score)
        return round(score, 4)

    def rank_servers(self, servers: Iterable, *, user_region_hint: Optional[str] = None) -> List[ScoredServer]:
        baselines = self.collect_baselines()
        scored = [
            ScoredServer(
                server_id=getattr(server, "server_id", "unknown"),
                score=self.score_server(server, baselines=baselines, user_region_hint=user_region_hint),
                latency_ms=float(getattr(server, "latency_ms", 999.0) or 999.0),
            )
            for server in servers
        ]
        scored.sort(key=lambda item: item.score, reverse=True)
        return scored


_optimizer: Optional[GeoLatencyOptimizer] = None


def get_latency_optimizer() -> GeoLatencyOptimizer:
    global _optimizer
    if _optimizer is None:
        _optimizer = GeoLatencyOptimizer()
    return _optimizer
