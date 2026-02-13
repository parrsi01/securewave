from types import SimpleNamespace

from services.latency_optimizer import BaselineLatency, GeoLatencyOptimizer


def _server(server_id: str, region: str, latency_ms: float, performance: float = 90.0):
    return SimpleNamespace(
        server_id=server_id,
        region=region,
        latency_ms=latency_ms,
        performance_score=performance,
    )


def test_geo_optimizer_prefers_lowest_rtt_with_corridor_weighting():
    optimizer = GeoLatencyOptimizer()
    baselines = BaselineLatency(barbados_ms=85.0, frankfurt_ms=120.0, source="fallback")

    eu = _server("eu", "Europe", 95.0)
    us = _server("us", "Americas", 140.0)

    eu_score = optimizer.score_server(eu, baselines=baselines, user_region_hint="caribbean")
    us_score = optimizer.score_server(us, baselines=baselines, user_region_hint="caribbean")

    assert eu_score > us_score


def test_geo_optimizer_rank_servers_orders_descending_score(monkeypatch):
    optimizer = GeoLatencyOptimizer()
    monkeypatch.setattr(
        optimizer,
        "collect_baselines",
        lambda: BaselineLatency(barbados_ms=90.0, frankfurt_ms=130.0, source="fallback"),
    )

    servers = [
        _server("slow", "Europe", 210.0),
        _server("fast", "Europe", 65.0),
        _server("mid", "Americas", 120.0),
    ]
    ranked = optimizer.rank_servers(servers, user_region_hint="europe")

    assert ranked[0].server_id == "fast"
    assert ranked[0].score >= ranked[1].score >= ranked[2].score
