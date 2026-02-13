import json
from pathlib import Path

import pytest

from dev_tools.sandbox.benchmark.enforce_thresholds import compute_metrics, evaluate_thresholds, write_violations


def _write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [",".join(header)]
    for row in rows:
        lines.append(",".join(row))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_benchmark_threshold_violation_detected(tmp_path: Path):
    bench_dir = tmp_path / "benchmark"
    bench_dir.mkdir(parents=True)

    # Latency: p95 should be 300.
    _write_csv(
        bench_dir / "latency_distribution.csv",
        ["timestamp", "region", "endpoint", "iteration", "latency_ms", "source", "status"],
        [
            ["t", "barbados", "1.1.1.1", "1", "10", "measured", "ok"],
            ["t", "barbados", "1.1.1.1", "2", "300", "measured", "ok"],
        ],
    )

    # Packet loss and jitter.
    _write_csv(
        bench_dir / "packet_loss.csv",
        ["timestamp", "region", "endpoint", "sent", "received", "loss_pct", "jitter_ms", "avg_latency_ms", "source", "status"],
        [["t", "barbados", "1.1.1.1", "10", "10", "3.0", "55.0", "20.0", "measured", "ok"]],
    )

    # Throughput.
    _write_csv(
        bench_dir / "throughput_summary.csv",
        ["timestamp", "test_mode", "download_mbps", "upload_mbps", "duration_s", "source"],
        [["t", "synthetic", "5.0", "5.0", "8.0", "synthetic"]],
    )

    # Handshake performance json.
    (bench_dir / "handshake_performance_result.json").write_text(
        json.dumps({"iterations": 100, "success_count": 90}, indent=2),
        encoding="utf-8",
    )

    thresholds = {
        "max_p95_latency_ms": 200.0,
        "max_jitter_ms": 50.0,
        "max_packet_loss_pct": 2.0,
        "min_handshake_rate": 0.98,
        "min_throughput_mbps": 25.0,
    }

    metrics = compute_metrics(bench_dir)
    violations = evaluate_thresholds(metrics, thresholds)

    assert {v.metric for v in violations} == {
        "p95_latency_ms",
        "max_jitter_ms",
        "max_packet_loss_pct",
        "handshake_rate",
        "throughput_mbps",
    }

    out = tmp_path / "benchmark_violations.json"
    write_violations(out, thresholds_path=tmp_path / "thresholds.json", metrics=metrics, violations=violations)
    assert out.exists()


def test_benchmark_thresholds_pass(tmp_path: Path):
    bench_dir = tmp_path / "benchmark"
    bench_dir.mkdir(parents=True)

    _write_csv(
        bench_dir / "latency_distribution.csv",
        ["timestamp", "region", "endpoint", "iteration", "latency_ms", "source", "status"],
        [["t", "barbados", "1.1.1.1", "1", "20", "measured", "ok"]],
    )
    _write_csv(
        bench_dir / "packet_loss.csv",
        ["timestamp", "region", "endpoint", "sent", "received", "loss_pct", "jitter_ms", "avg_latency_ms", "source", "status"],
        [["t", "barbados", "1.1.1.1", "10", "10", "0.0", "1.0", "20.0", "measured", "ok"]],
    )
    _write_csv(
        bench_dir / "throughput_summary.csv",
        ["timestamp", "test_mode", "download_mbps", "upload_mbps", "duration_s", "source"],
        [["t", "synthetic", "100.0", "100.0", "8.0", "synthetic"]],
    )
    (bench_dir / "handshake_performance_result.json").write_text(
        json.dumps({"iterations": 100, "success_count": 100}, indent=2),
        encoding="utf-8",
    )

    thresholds = {
        "max_p95_latency_ms": 200.0,
        "max_jitter_ms": 50.0,
        "max_packet_loss_pct": 2.0,
        "min_handshake_rate": 0.98,
        "min_throughput_mbps": 25.0,
    }

    metrics = compute_metrics(bench_dir)
    violations = evaluate_thresholds(metrics, thresholds)
    assert violations == []
