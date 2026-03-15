"""
Unit tests for services.server_ranker — weighted server selection algorithm.
"""
from __future__ import annotations

import pytest

from models.vpn_server import VPNServer
import models.vpn_connection  # noqa: F401 — register relationship for VPNServer mapper

from services.server_ranker import (
    _latency_score,
    _load_score_inv,
    _region_score,
    rank_servers,
    select_best,
    LATENCY_CAP_MS,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _srv(**overrides) -> VPNServer:
    defaults = dict(
        server_id="test-1",
        location="Test",
        country="Testland",
        country_code="TT",
        city="Testville",
        hcloud_location="fsn1",
        public_ip="10.0.0.1",
        endpoint="10.0.0.1:51820",
        wg_public_key="key==",
        wg_private_key_encrypted="enc",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        latency_ms=25.0,
        load_score=0.0,
        region="Europe",
    )
    defaults.update(overrides)
    return VPNServer(**defaults)


# ---------------------------------------------------------------------------
# Latency score
# ---------------------------------------------------------------------------


class TestLatencyScore:
    def test_zero_latency_scores_one(self):
        assert _latency_score(_srv(latency_ms=0)) == 1.0

    def test_max_latency_scores_zero(self):
        assert _latency_score(_srv(latency_ms=LATENCY_CAP_MS)) == 0.0

    def test_above_cap_scores_zero(self):
        assert _latency_score(_srv(latency_ms=999)) == 0.0

    def test_midpoint_scores_half(self):
        score = _latency_score(_srv(latency_ms=LATENCY_CAP_MS / 2))
        assert abs(score - 0.5) < 0.001

    def test_none_latency_treated_as_zero(self):
        assert _latency_score(_srv(latency_ms=None)) == 1.0

    def test_low_latency_scores_high(self):
        score = _latency_score(_srv(latency_ms=10))
        assert score > 0.95


# ---------------------------------------------------------------------------
# Load score (inverted)
# ---------------------------------------------------------------------------


class TestLoadScoreInv:
    def test_idle_server_scores_one(self):
        assert _load_score_inv(_srv(load_score=0.0)) == 1.0

    def test_saturated_server_scores_zero(self):
        assert _load_score_inv(_srv(load_score=1.0)) == 0.0

    def test_half_loaded(self):
        assert abs(_load_score_inv(_srv(load_score=0.5)) - 0.5) < 0.001

    def test_none_load_treated_as_idle(self):
        assert _load_score_inv(_srv(load_score=None)) == 1.0

    def test_clamped_above_one(self):
        assert _load_score_inv(_srv(load_score=1.5)) == 0.0


# ---------------------------------------------------------------------------
# Region score
# ---------------------------------------------------------------------------


class TestRegionScore:
    def test_exact_match(self):
        assert _region_score(_srv(region="Europe"), "europe") == 1.0

    def test_second_tier(self):
        assert _region_score(_srv(region="Europe"), "americas") == 0.5

    def test_no_match(self):
        assert _region_score(_srv(region="Americas"), "europe") == 0.0

    def test_no_hint_is_neutral(self):
        assert _region_score(_srv(region="Europe"), None) == 0.5

    def test_unknown_hint_is_neutral(self):
        assert _region_score(_srv(region="Europe"), "mars") == 0.5

    def test_asia_prefers_asia_then_europe(self):
        assert _region_score(_srv(region="Asia"), "asia") == 1.0
        assert _region_score(_srv(region="Europe"), "asia") == 0.5
        assert _region_score(_srv(region="Americas"), "asia") == 0.0


# ---------------------------------------------------------------------------
# rank_servers
# ---------------------------------------------------------------------------


class TestRankServers:
    def test_empty_candidates(self):
        assert rank_servers([]) == []

    def test_single_server(self):
        ranked = rank_servers([_srv()])
        assert len(ranked) == 1
        assert ranked[0].composite_score > 0

    def test_lower_latency_wins(self):
        """Server with lower latency should rank higher, all else equal."""
        fast = _srv(server_id="fast", latency_ms=10, load_score=0.1, region="Europe")
        slow = _srv(server_id="slow", latency_ms=300, load_score=0.1, region="Europe")
        ranked = rank_servers([slow, fast], region_hint="europe")
        assert ranked[0].server_id == "fast"

    def test_lower_load_wins_when_latency_equal(self):
        """Server with lower load should win when latency is identical."""
        idle = _srv(server_id="idle", latency_ms=50, load_score=0.1, region="Europe")
        busy = _srv(server_id="busy", latency_ms=50, load_score=0.8, region="Europe")
        ranked = rank_servers([busy, idle], region_hint="europe")
        assert ranked[0].server_id == "idle"

    def test_region_match_boosts_score(self):
        """Region-matching server should beat a non-matching one, all else equal."""
        eu = _srv(server_id="eu", latency_ms=50, load_score=0.2, region="Europe")
        us = _srv(server_id="us", latency_ms=50, load_score=0.2, region="Americas")
        ranked = rank_servers([us, eu], region_hint="europe")
        assert ranked[0].server_id == "eu"

    def test_very_fast_remote_can_beat_slow_local(self):
        """A fast remote server should beat a slow local one despite region mismatch."""
        fast_remote = _srv(server_id="fast-remote", latency_ms=20, load_score=0.1, region="Americas")
        slow_local = _srv(server_id="slow-local", latency_ms=400, load_score=0.5, region="Europe")
        ranked = rank_servers([slow_local, fast_remote], region_hint="europe")
        assert ranked[0].server_id == "fast-remote"

    def test_worked_example_from_docs(self):
        """Validate the worked example from docs/server_selection_algorithm.md."""
        fra = _srv(server_id="de-fra-1", latency_ms=25, load_score=0.15, region="Europe")
        nyc = _srv(server_id="us-nyc-1", latency_ms=120, load_score=0.05, region="Americas")
        nue = _srv(server_id="de-nue-1", latency_ms=30, load_score=0.60, region="Europe")

        ranked = rank_servers([nyc, nue, fra], region_hint="europe")
        assert ranked[0].server_id == "de-fra-1"
        assert ranked[1].server_id == "de-nue-1"
        assert ranked[2].server_id == "us-nyc-1"

        # Verify approximate scores from the worked example.
        assert abs(ranked[0].composite_score - 0.930) < 0.01
        assert abs(ranked[2].composite_score - 0.665) < 0.01


# ---------------------------------------------------------------------------
# select_best
# ---------------------------------------------------------------------------


class TestSelectBest:
    def test_returns_none_for_empty(self):
        assert select_best([]) is None

    def test_returns_vpn_server_object(self):
        srv = _srv()
        result = select_best([srv])
        assert result is srv

    def test_returns_best_server(self):
        fast = _srv(server_id="fast", latency_ms=10, load_score=0.0)
        slow = _srv(server_id="slow", latency_ms=400, load_score=0.9)
        result = select_best([slow, fast])
        assert result.server_id == "fast"


# ---------------------------------------------------------------------------
# Integration: ranking respects no-hint neutrality
# ---------------------------------------------------------------------------


def test_no_region_hint_does_not_penalise_any_region():
    """Without a region hint, all regions should be treated equally."""
    eu = _srv(server_id="eu", latency_ms=50, load_score=0.2, region="Europe")
    us = _srv(server_id="us", latency_ms=50, load_score=0.2, region="Americas")
    asia = _srv(server_id="asia", latency_ms=50, load_score=0.2, region="Asia")

    ranked = rank_servers([eu, us, asia], region_hint=None)
    scores = {r.server_id: r.region_score for r in ranked}
    assert scores["eu"] == scores["us"] == scores["asia"] == 0.5
