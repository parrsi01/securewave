#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${BENCHMARK_OUTPUT_DIR:-$ROOT_DIR/artifacts/benchmark}"
TIMEOUT_SECONDS="${BENCHMARK_TIMEOUT_SECONDS:-240}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
STRICT=false

for arg in "$@"; do
  case "$arg" in
    --strict)
      STRICT=true
      ;;
  esac
done

if [[ "${BENCHMARK_STRICT:-false}" == "true" || "${BENCHMARK_STRICT:-0}" == "1" ]]; then
  STRICT=true
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python}"
fi

mkdir -p "$OUT_DIR"

run_one() {
  local name="$1"
  shift
  if timeout "$TIMEOUT_SECONDS" "$PYTHON_BIN" "$@"; then
    echo "[PASS] $name"
    return 0
  else
    echo "[FAIL] $name"
    return 1
  fi
}

pass_count=0
fail_count=0

if run_one "ping_latency" "$ROOT_DIR/sandbox/benchmark/ping_latency.py" --output-dir "$OUT_DIR"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "jitter_packet_loss" "$ROOT_DIR/sandbox/benchmark/jitter_packet_loss.py" --output-dir "$OUT_DIR"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "handshake_performance" "$ROOT_DIR/sandbox/benchmark/handshake_performance.py" --output-dir "$OUT_DIR"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "throughput_test" "$ROOT_DIR/sandbox/benchmark/throughput_test.py" --output-dir "$OUT_DIR"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "competitor_probe" "$ROOT_DIR/sandbox/benchmark/competitor_probe.py" \
  --output-dir "$OUT_DIR" \
  --latency-csv "$OUT_DIR/latency_distribution.csv" \
  --competitors "${BENCHMARK_COMPETITOR_ENDPOINTS:-}"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

export BENCHMARK_OUT_DIR="$OUT_DIR"

"$PYTHON_BIN" - <<'PY'
import csv
import json
import os
from datetime import datetime, timezone
from pathlib import Path

out_dir = Path(os.environ["BENCHMARK_OUT_DIR"])
result_files = [
    "ping_latency_result.json",
    "jitter_packet_loss_result.json",
    "handshake_performance_result.json",
    "throughput_test_result.json",
    "competitor_probe_result.json",
]
results = []
for name in result_files:
    path = out_dir / name
    if path.exists():
        results.append(json.loads(path.read_text(encoding="utf-8")))

passed = sum(1 for item in results if item.get("overall_status") == "pass")
failed = len(results) - passed

latency_rows = 0
packet_rows = 0
handshake_rows = 0
throughput_rows = 0

for filename, key in [
    ("latency_distribution.csv", "latency_rows"),
    ("packet_loss.csv", "packet_rows"),
    ("handshake_times.csv", "handshake_rows"),
    ("throughput_summary.csv", "throughput_rows"),
]:
    path = out_dir / filename
    if path.exists():
        with path.open("r", encoding="utf-8") as fh:
            reader = csv.reader(fh)
            next(reader, None)
            count = sum(1 for _ in reader)
        if key == "latency_rows":
            latency_rows = count
        elif key == "packet_rows":
            packet_rows = count
        elif key == "handshake_rows":
            handshake_rows = count
        elif key == "throughput_rows":
            throughput_rows = count

summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "total_harnesses": len(results),
    "passed": passed,
    "failed": failed,
    "data_points": {
        "latency_rows": latency_rows,
        "packet_rows": packet_rows,
        "handshake_rows": handshake_rows,
        "throughput_rows": throughput_rows,
    },
    "results": results,
}
(out_dir / "benchmark_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

lines = [
    "# Benchmark Report",
    "",
    f"- Generated: `{summary['generated_at']}`",
    f"- Harnesses: **{summary['total_harnesses']}**",
    f"- Passed: **{passed}**",
    f"- Failed: **{failed}**",
    "",
    "## Dataset Sizes",
    "",
    f"- `latency_distribution.csv`: **{latency_rows}** rows",
    f"- `packet_loss.csv`: **{packet_rows}** rows",
    f"- `handshake_times.csv`: **{handshake_rows}** rows",
    f"- `throughput_summary.csv`: **{throughput_rows}** rows",
    "",
    "## Harness Results",
    "",
    "| Harness | Status |",
    "|---|---|",
]
for item in results:
    lines.append(f"| {item.get('harness', 'unknown')} | {item.get('overall_status', 'unknown')} |")
(out_dir / "benchmark_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

html_rows = "".join(
    f"<tr><td>{item.get('harness', 'unknown')}</td><td>{item.get('overall_status', 'unknown')}</td></tr>"
    for item in results
)
html = (
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Benchmark Report</title>"
    "<style>body{font-family:Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}"
    "th,td{border:1px solid #ccc;padding:8px;text-align:left}th{background:#f5f5f5}</style>"
    "</head><body>"
    "<h1>Benchmark Report</h1>"
    f"<p><strong>Generated:</strong> {summary['generated_at']}</p>"
    f"<p><strong>Passed:</strong> {passed} / {summary['total_harnesses']}</p>"
    "<table><thead><tr><th>Harness</th><th>Status</th></tr></thead>"
    f"<tbody>{html_rows}</tbody></table>"
    "</body></html>"
)
(out_dir / "benchmark_report.html").write_text(html, encoding="utf-8")
PY

enforce_thresholds() {
  local strict_flag=()
  if [[ "$STRICT" == "true" ]]; then
    strict_flag=(--strict)
  fi

  if "$PYTHON_BIN" "$ROOT_DIR/sandbox/benchmark/enforce_thresholds.py" \
    --benchmark-dir "$OUT_DIR" \
    --thresholds "$ROOT_DIR/benchmarks/thresholds.json" \
    --output "$OUT_DIR/benchmark_violations.json" \
    "${strict_flag[@]}"; then
    echo "[PASS] benchmark_thresholds"
    return 0
  else
    echo "[FAIL] benchmark_thresholds"
    if [[ -f "$OUT_DIR/benchmark_violations.json" ]]; then
      echo "::group::benchmark_violations.json"
      cat "$OUT_DIR/benchmark_violations.json" || true
      echo "::endgroup::"
    fi
    return 1
  fi
}

if enforce_thresholds; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

echo "Benchmark suite complete. Summary: $OUT_DIR/benchmark_summary.json"
