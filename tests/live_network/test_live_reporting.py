import csv
import json
from pathlib import Path

from dev_tools.sandbox.live_validation.reporting import generate_readiness_report


def _write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def test_generate_readiness_report_pass(tmp_path: Path):
    out_dir = tmp_path / "live_validation"
    out_dir.mkdir(parents=True)

    _write_csv(
        out_dir / "handshake_stats.csv",
        ["timestamp", "platform", "worker", "cycle", "handshake_ms", "success"],
        [
            ["t", "linux", "1", "1", "120", "true"],
            ["t", "linux", "1", "2", "180", "true"],
            ["t", "linux", "1", "3", "240", "true"],
        ],
    )

    _write_csv(
        out_dir / "dns_checks.csv",
        ["timestamp", "status"],
        [["t", "ok"], ["t", "ok"]],
    )

    _write_csv(
        out_dir / "geo_latency_report.csv",
        ["timestamp", "region", "effective_latency_ms"],
        [["t", "barbados", "95"], ["t", "europe", "62"]],
    )

    (out_dir / "live_e2e_result.json").write_text(
        json.dumps({"overall_status": "pass", "geo_status": "pass"}),
        encoding="utf-8",
    )
    (out_dir / "live_stress_summary.json").write_text(
        json.dumps({"overall_status": "pass"}),
        encoding="utf-8",
    )
    (out_dir / "network_faults_result.json").write_text(
        json.dumps({"overall_status": "simulated"}),
        encoding="utf-8",
    )

    summary = generate_readiness_report(out_dir)
    assert summary["overall_status"] in {"pass", "warn"}
    assert summary["readiness_score"] >= 80
    assert summary["handshake"]["p95_ms"] > 0
    assert (out_dir / "validation_summary.json").exists()
    assert (out_dir / "PRODUCTION_NETWORK_READINESS.md").exists()


def test_generate_readiness_report_fail(tmp_path: Path):
    out_dir = tmp_path / "live_validation"
    out_dir.mkdir(parents=True)

    _write_csv(
        out_dir / "handshake_stats.csv",
        ["timestamp", "platform", "worker", "cycle", "handshake_ms", "success"],
        [["t", "linux", "1", "1", "0", "false"]],
    )

    _write_csv(
        out_dir / "dns_checks.csv",
        ["timestamp", "status"],
        [["t", "failed"]],
    )

    _write_csv(
        out_dir / "geo_latency_report.csv",
        ["timestamp", "region", "effective_latency_ms"],
        [["t", "barbados", "250"]],
    )

    (out_dir / "live_e2e_result.json").write_text(
        json.dumps({"overall_status": "fail"}),
        encoding="utf-8",
    )
    (out_dir / "live_stress_summary.json").write_text(
        json.dumps({"overall_status": "fail"}),
        encoding="utf-8",
    )
    (out_dir / "network_faults_result.json").write_text(
        json.dumps({"overall_status": "fail"}),
        encoding="utf-8",
    )

    summary = generate_readiness_report(out_dir)
    assert summary["overall_status"] == "fail"
    assert summary["readiness_score"] < 60
