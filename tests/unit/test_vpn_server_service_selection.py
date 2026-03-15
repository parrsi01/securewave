from types import SimpleNamespace

from models.vpn_server import VPNServer
from services.vpn_server_service import VPNServerService


def _seed_server(
    db,
    *,
    server_id: str,
    latency_ms: float,
    health_status: str = "healthy",
    status: str = "active",
):
    server = VPNServer(
        server_id=server_id,
        location="Test",
        country="Testland",
        country_code="TT",
        city="Test City",
        region="Americas",
        hcloud_location="ash",
        public_ip=f"203.0.113.{10 + len(server_id)}",
        endpoint=f"203.0.113.{10 + len(server_id)}:51820",
        wg_public_key=f"test-public-key-{server_id}",
        wg_private_key_encrypted="encrypted-key",
        status=status,
        health_status=health_status,
        hcloud_server_state="running",
        performance_score=95.0,
        latency_ms=latency_ms,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


class _StubLatencyOptimizer:
    def rank_servers(self, servers, user_region_hint=None):
        ranked = sorted(servers, key=lambda item: float(item.latency_ms or 9999.0))
        return [SimpleNamespace(server_id=item.server_id, score=1.0) for item in ranked]


class _StubVpnOptimizer:
    def __init__(self, suggested_server_id: str):
        self.suggested_server_id = suggested_server_id

    def select_optimal_server(self, user_id, user_location=None, is_premium=False):
        return {"server_id": self.suggested_server_id}


def test_allocate_server_for_user_falls_back_to_lowest_latency_when_optimizer_misses(
    db,
    test_user,
    monkeypatch,
):
    fast = _seed_server(db, server_id="fast-1", latency_ms=18.0)
    _seed_server(db, server_id="mid-1", latency_ms=45.0)
    _seed_server(db, server_id="slow-1", latency_ms=90.0)

    monkeypatch.setattr(
        "services.vpn_optimizer.get_vpn_optimizer",
        lambda: _StubVpnOptimizer("does-not-exist"),
    )
    monkeypatch.setattr(
        "services.latency_optimizer.get_latency_optimizer",
        lambda: _StubLatencyOptimizer(),
    )

    selected = VPNServerService.allocate_server_for_user(db, test_user)

    assert selected is not None
    assert selected.server_id == fast.server_id


def test_get_active_servers_excludes_unhealthy_and_inactive_nodes(db):
    healthy = _seed_server(db, server_id="healthy-1", latency_ms=20.0, health_status="healthy")
    degraded = _seed_server(db, server_id="degraded-1", latency_ms=30.0, health_status="degraded")
    _seed_server(db, server_id="unstable-1", latency_ms=10.0, health_status="unstable")
    _seed_server(db, server_id="offline-1", latency_ms=5.0, health_status="healthy", status="maintenance")

    server_ids = {server.server_id for server in VPNServerService.get_active_servers(db, user_tier="free")}

    assert healthy.server_id in server_ids
    assert degraded.server_id in server_ids
    assert "unstable-1" not in server_ids
    assert "offline-1" not in server_ids
