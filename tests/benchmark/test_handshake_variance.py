from dev_tools.sandbox.benchmark.handshake_performance import compute_handshake_stats


def test_handshake_variance():
    stats = compute_handshake_stats([10.0, 12.5, 18.2, 17.4, 15.0])

    assert stats["samples"] == 5
    assert stats["avg_latency_ms"] > 0
    assert stats["p95_latency_ms"] >= stats["p50_latency_ms"]
    assert stats["variance_ms2"] > 0
