from services.wireguard_tuning import tune_wireguard


def test_adaptive_mtu_degrades_for_unstable_links(monkeypatch):
    monkeypatch.setenv("SECUREWAVE_MTU_PROBE", "false")

    tuning = tune_wireguard(
        endpoint="1.1.1.1:51820",
        client_ip="8.8.8.8",
        forwarded_for=None,
        observed_latency_ms=320.0,
        device_type="windows",
        packet_loss=0.14,
        jitter_ms=85.0,
        server_health_status="unstable",
    )

    assert tuning.mtu == 1320
    assert tuning.keepalive_seconds > 0


def test_adaptive_mtu_prefers_high_mtu_on_healthy_path(monkeypatch):
    monkeypatch.setenv("SECUREWAVE_MTU_PROBE", "false")

    tuning = tune_wireguard(
        endpoint="1.1.1.1:51820",
        client_ip="8.8.4.4",
        forwarded_for=None,
        observed_latency_ms=28.0,
        device_type="windows",
        packet_loss=0.0,
        jitter_ms=3.0,
        server_health_status="healthy",
    )

    assert tuning.mtu in {1400, 1420}
    assert tuning.keepalive_seconds > 0
