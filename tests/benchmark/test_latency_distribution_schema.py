import csv
from pathlib import Path

from sandbox.benchmark.ping_latency import run_benchmark


EXPECTED_COLUMNS = {
    "timestamp",
    "region",
    "endpoint",
    "iteration",
    "latency_ms",
    "source",
    "status",
}


def test_latency_distribution_schema(tmp_path: Path):
    payload = run_benchmark(
        output_dir=tmp_path,
        targets=[("barbados", "1.1.1.1"), ("frankfurt", "8.8.8.8")],
        samples=3,
    )
    assert payload["overall_status"] == "pass"

    csv_path = tmp_path / "latency_distribution.csv"
    assert csv_path.exists()

    with csv_path.open("r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        assert set(reader.fieldnames or []) == EXPECTED_COLUMNS
        rows = list(reader)

    assert len(rows) == 6
    assert all(float(row["latency_ms"]) > 0 for row in rows)
