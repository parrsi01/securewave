"""
Unit tests for select_failover_servers() — backup endpoint selection for VPN profiles.
"""
from __future__ import annotations

import pytest

from models.vpn_server import VPNServer
import models.vpn_connection  # noqa: F401 — register relationship for VPNServer mapper

from routes.vpn import select_failover_servers, FailoverEndpoint, MAX_FAILOVER_ENDPOINTS


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_next_id = 0


def _srv(**overrides) -> VPNServer:
    global _next_id
    _next_id += 1
    defaults = dict(
        id=_next_id,
        server_id=f"test-{_next_id}",
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


@pytest.fixture(autouse=True)
def _reset_id():
    global _next_id
    _next_id = 0
    yield


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestSelectFailoverServers:
    def test_empty_candidates_returns_empty(self):
        primary = _srv(server_id="primary")
        assert select_failover_servers([], primary) == []

    def test_only_primary_returns_empty(self):
        primary = _srv(server_id="only")
        assert select_failover_servers([primary], primary) == []

    def test_two_candidates_one_backup(self):
        primary = _srv(server_id="primary")
        backup = _srv(server_id="backup", endpoint="10.0.0.2:51820", wg_public_key="bk==")
        result = select_failover_servers([primary, backup], primary)
        assert len(result) == 1
        assert result[0].server_id == "backup"
        assert result[0].endpoint == "10.0.0.2:51820"
        assert result[0].public_key == "bk=="

    def test_returns_failover_endpoint_instances(self):
        primary = _srv(server_id="p")
        b1 = _srv(server_id="b1")
        result = select_failover_servers([primary, b1], primary)
        assert all(isinstance(ep, FailoverEndpoint) for ep in result)

    def test_max_two_backups_by_default(self):
        primary = _srv(server_id="primary")
        extras = [_srv(server_id=f"s{i}") for i in range(5)]
        result = select_failover_servers([primary] + extras, primary)
        assert len(result) == MAX_FAILOVER_ENDPOINTS

    def test_custom_max_backups(self):
        primary = _srv(server_id="primary")
        extras = [_srv(server_id=f"s{i}") for i in range(5)]
        result = select_failover_servers([primary] + extras, primary, max_backups=1)
        assert len(result) == 1

    def test_primary_excluded_from_backups(self):
        primary = _srv(server_id="primary")
        b1 = _srv(server_id="b1")
        b2 = _srv(server_id="b2")
        result = select_failover_servers([primary, b1, b2], primary)
        ids = [ep.server_id for ep in result]
        assert "primary" not in ids

    def test_backups_ranked_by_score(self):
        """Lower latency backup should appear first."""
        primary = _srv(server_id="primary")
        fast = _srv(server_id="fast", latency_ms=10, load_score=0.1)
        slow = _srv(server_id="slow", latency_ms=300, load_score=0.1)
        result = select_failover_servers([primary, slow, fast], primary)
        assert result[0].server_id == "fast"
        assert result[1].server_id == "slow"

    def test_region_hint_affects_backup_order(self):
        """Region-matching backup should rank higher."""
        primary = _srv(server_id="primary", region="Americas")
        eu = _srv(server_id="eu", latency_ms=50, load_score=0.2, region="Europe")
        us = _srv(server_id="us", latency_ms=50, load_score=0.2, region="Americas")
        result = select_failover_servers(
            [primary, eu, us], primary, region_hint="americas",
        )
        assert result[0].server_id == "us"

    def test_location_field_populated(self):
        primary = _srv(server_id="p")
        backup = _srv(server_id="b", city="Frankfurt", country="Germany")
        result = select_failover_servers([primary, backup], primary)
        assert result[0].location == "Frankfurt, Germany"


class TestFailoverEndpointModel:
    def test_serialization(self):
        ep = FailoverEndpoint(
            server_id="de-fra-1",
            endpoint="10.0.0.1:51820",
            public_key="abc==",
            location="Frankfurt, Germany",
        )
        data = ep.model_dump()
        assert data["server_id"] == "de-fra-1"
        assert data["endpoint"] == "10.0.0.1:51820"
        assert data["public_key"] == "abc=="
        assert data["location"] == "Frankfurt, Germany"
