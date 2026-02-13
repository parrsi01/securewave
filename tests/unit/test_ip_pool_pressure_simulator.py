from pathlib import Path

from sandbox.ip_pool_pressure.simulator import IPPoolPressureConfig, simulate_ip_pool_pressure


def test_ip_pool_pressure_simulator_validates_uniqueness_and_reclaim(tmp_path):
    cfg = IPPoolPressureConfig(
        peers=50,
        cycles=3,
        churn_per_cycle=10,
        seed=123,
        base_cidr="10.240.0.0/22",
        max_blocks=1,
        reserved_hosts=970,  # capacity ~= 52, keeps pressure high
        alert_threshold_pct=80,
    )
    report = simulate_ip_pool_pressure(cfg=cfg, output_dir=Path(tmp_path))

    cycles = report["cycles"]
    assert cycles, "expected cycle rows"
    assert all(row["unique_active_ips"] for row in cycles)
    assert any(row["reclaimed_this_cycle"] > 0 for row in cycles)


def test_ip_pool_pressure_simulator_emits_exhaustion_errors_and_alerts(tmp_path):
    cfg = IPPoolPressureConfig(
        peers=50,
        cycles=1,
        churn_per_cycle=0,
        seed=42,
        base_cidr="10.241.0.0/22",
        max_blocks=1,
        reserved_hosts=970,  # capacity ~= 52
        alert_threshold_pct=80,
    )
    report = simulate_ip_pool_pressure(cfg=cfg, output_dir=Path(tmp_path))
    summary = report["summary"]
    assert summary["exhaustion_errors_total"] >= 1
    assert summary["final_pool_stats"]["alert"] is not None

