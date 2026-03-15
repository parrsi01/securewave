"""
Deterministic server ranking for VPN auto-selection.

Scores each candidate on three axes and returns them sorted best-first.

    composite_score = W_LATENCY  * latency_score
                    + W_LOAD     * load_score_inv
                    + W_REGION   * region_score

Weights are configurable via environment variables.

See docs/server_selection_algorithm.md for the full specification.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import List, Optional, Sequence

from models.vpn_server import VPNServer


# ---------------------------------------------------------------------------
# Tunable weights (env-overridable, must sum to 1.0 by convention)
# ---------------------------------------------------------------------------

def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw.strip())
    except ValueError:
        return default


W_LATENCY = _env_float("VPN_RANK_W_LATENCY", 0.50)
W_LOAD = _env_float("VPN_RANK_W_LOAD", 0.30)
W_REGION = _env_float("VPN_RANK_W_REGION", 0.20)

# Latency beyond this value scores 0.
LATENCY_CAP_MS = _env_float("VPN_RANK_LATENCY_CAP_MS", 500.0)

# Region affinity mapping: region_hint → ordered list of preferred regions.
_REGION_AFFINITY: dict[str, list[str]] = {
    "europe": ["Europe"],
    "eu": ["Europe"],
    "americas": ["Americas", "Europe"],
    "caribbean": ["Americas", "Europe"],
    "north_america": ["Americas", "Europe"],
    "asia": ["Asia", "Europe"],
    "oceania": ["Asia", "Americas"],
    "africa": ["Europe", "Americas"],
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RankedServer:
    """Result of ranking a single server candidate."""

    server_id: str
    composite_score: float
    latency_score: float
    load_score_inv: float
    region_score: float


def rank_servers(
    candidates: Sequence[VPNServer],
    *,
    region_hint: Optional[str] = None,
) -> List[RankedServer]:
    """
    Score and sort *candidates* best-first.

    Args:
        candidates: Active, tier-filtered VPNServer instances.
        region_hint: Optional geographic hint (e.g. ``"europe"``).

    Returns:
        List of ``RankedServer`` sorted by ``composite_score`` descending.
    """
    if not candidates:
        return []

    results: list[RankedServer] = []
    for server in candidates:
        lat = _latency_score(server)
        load = _load_score_inv(server)
        reg = _region_score(server, region_hint)
        composite = W_LATENCY * lat + W_LOAD * load + W_REGION * reg
        results.append(
            RankedServer(
                server_id=server.server_id,
                composite_score=round(composite, 6),
                latency_score=round(lat, 6),
                load_score_inv=round(load, 6),
                region_score=round(reg, 6),
            )
        )

    results.sort(key=lambda r: r.composite_score, reverse=True)
    return results


def select_best(
    candidates: Sequence[VPNServer],
    *,
    region_hint: Optional[str] = None,
) -> Optional[VPNServer]:
    """
    Convenience wrapper: returns the single best candidate, or ``None``.
    """
    ranked = rank_servers(candidates, region_hint=region_hint)
    if not ranked:
        return None
    best_id = ranked[0].server_id
    for server in candidates:
        if server.server_id == best_id:
            return server
    return None


# ---------------------------------------------------------------------------
# Scoring components
# ---------------------------------------------------------------------------


def _latency_score(server: VPNServer) -> float:
    """
    0.0 (worst) to 1.0 (best).

    ``latency_ms == 0`` maps to 1.0.
    ``latency_ms >= LATENCY_CAP_MS`` maps to 0.0.
    Linear interpolation between.
    """
    latency = float(server.latency_ms or 0.0)
    if latency <= 0:
        return 1.0
    if latency >= LATENCY_CAP_MS:
        return 0.0
    return 1.0 - (latency / LATENCY_CAP_MS)


def _load_score_inv(server: VPNServer) -> float:
    """
    Inverse of ``load_score``: 1.0 when idle, 0.0 when saturated.

    Uses the precomputed ``VPNServer.load_score`` (0.0–1.0).
    """
    return 1.0 - min(1.0, max(0.0, float(server.load_score or 0.0)))


def _region_score(server: VPNServer, region_hint: Optional[str]) -> float:
    """
    1.0 if server.region matches the user's preferred region,
    0.5 for second-tier affinity, 0.25 for third-tier, 0.0 otherwise.

    When *region_hint* is ``None``, all servers score 0.5 (neutral).
    """
    if not region_hint:
        return 0.5

    hint = region_hint.strip().lower()
    preferred = _REGION_AFFINITY.get(hint)
    if not preferred:
        return 0.5  # Unknown hint — treat as neutral.

    server_region = (server.region or "").strip()
    for i, pref in enumerate(preferred):
        if server_region.lower() == pref.lower():
            # First match = 1.0, second = 0.5, third = 0.25, etc.
            return 1.0 / (i + 1)

    return 0.0
