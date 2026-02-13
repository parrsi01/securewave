#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIR="${LEAK_OUTPUT_DIR:-$ROOT_DIR/artifacts/leak_tests}"
TIMEOUT_SECONDS="${LEAK_TIMEOUT_SECONDS:-180}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python}"
fi
STRICT=false

for arg in "$@"; do
  case "$arg" in
    --strict)
      STRICT=true
      ;;
  esac
done

if [[ "${LEAK_STRICT:-false}" == "true" || "${LEAK_STRICT:-0}" == "1" ]]; then
  STRICT=true
fi

mkdir -p "$OUT_DIR"

run_one() {
  local name="$1"
  local script="$2"
  shift 2
  if timeout "$TIMEOUT_SECONDS" "$PYTHON_BIN" "$script" --output-dir "$OUT_DIR" "$@"; then
    echo "[PASS] $name"
    return 0
  else
    echo "[FAIL] $name"
    return 1
  fi
}

pass_count=0
fail_count=0

if run_one "dns_leak_test" "$ROOT_DIR/dev_tools/sandbox/leak_tests/dns_leak_test.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "ipv6_leak_test" "$ROOT_DIR/dev_tools/sandbox/leak_tests/ipv6_leak_test.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "route_table_test" "$ROOT_DIR/dev_tools/sandbox/leak_tests/route_table_test.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "interface_flap_test" "$ROOT_DIR/dev_tools/sandbox/leak_tests/interface_flap_test.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

"$PYTHON_BIN" - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

out_dir = Path(r"$OUT_DIR")
result_files = [
    "dns_leak_result.json",
    "ipv6_leak_result.json",
    "route_table_result.json",
    "interface_flap_result.json",
]
results = []
for name in result_files:
    path = out_dir / name
    if path.exists():
        results.append(json.loads(path.read_text(encoding="utf-8")))

passed = sum(1 for item in results if item.get("overall_status") == "pass")
failed = len(results) - passed
payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "total": len(results),
    "passed": passed,
    "failed": failed,
    "results": results,
}
(out_dir / "leak_summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

lines = [
    "# Leak Validation Summary",
    "",
    f"- Total harnesses: **{len(results)}**",
    f"- Passed: **{passed}**",
    f"- Failed: **{failed}**",
    "",
    "| Harness | Status |",
    "|---|---|",
]
for result in results:
    lines.append(f"| {result.get('harness')} | {result.get('overall_status')} |")
(out_dir / "leak_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

strict_flag=()
if [[ "$STRICT" == "true" ]]; then
  strict_flag=(--strict)
fi

if "$PYTHON_BIN" "$ROOT_DIR/dev_tools/sandbox/leak_tests/enforce_thresholds.py" \
  --leak-dir "$OUT_DIR" \
  --thresholds "$ROOT_DIR/dev_tools/leak/leak_thresholds.json" \
  --output "$OUT_DIR/leak_violations.json" \
  "${strict_flag[@]}"; then
  echo "[PASS] leak_thresholds"
  ((pass_count+=1))
else
  echo "[FAIL] leak_thresholds"
  if [[ -f "$OUT_DIR/leak_violations.json" ]]; then
    echo "::group::leak_violations.json"
    cat "$OUT_DIR/leak_violations.json" || true
    echo "::endgroup::"
  fi
  ((fail_count+=1))
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

echo "Leak suite complete. Summary: $OUT_DIR/leak_summary.json"
