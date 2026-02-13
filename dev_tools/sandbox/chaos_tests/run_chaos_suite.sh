#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIR="${CHAOS_OUTPUT_DIR:-$ROOT_DIR/artifacts/chaos_tests}"
TIMEOUT_SECONDS="${CHAOS_TIMEOUT_SECONDS:-180}"
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

if [[ "${CHAOS_STRICT:-false}" == "true" || "${CHAOS_STRICT:-0}" == "1" ]]; then
  STRICT=true
fi

mkdir -p "$OUT_DIR"

run_one() {
  local name="$1"
  local script="$2"
  if timeout "$TIMEOUT_SECONDS" "$PYTHON_BIN" "$script" --output-dir "$OUT_DIR"; then
    echo "[PASS] $name"
    return 0
  else
    echo "[FAIL] $name"
    return 1
  fi
}

pass_count=0
fail_count=0

if run_one "network_drop" "$ROOT_DIR/dev_tools/sandbox/chaos_tests/network_drop.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "db_disconnect" "$ROOT_DIR/dev_tools/sandbox/chaos_tests/db_disconnect.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

if run_one "jwt_replay_attack" "$ROOT_DIR/dev_tools/sandbox/chaos_tests/jwt_replay_attack.py"; then
  ((pass_count+=1))
else
  ((fail_count+=1))
fi

summary_json="$OUT_DIR/chaos_summary.json"
summary_md="$OUT_DIR/chaos_summary.md"

"$PYTHON_BIN" - <<PY
import json
from pathlib import Path
from datetime import datetime, timezone

out_dir = Path(r"$OUT_DIR")
results = []
for name in ["network_drop", "db_disconnect", "jwt_replay_attack"]:
    path = out_dir / f"{name}_result.json"
    if path.exists():
        results.append(json.loads(path.read_text(encoding="utf-8")))

passed = sum(1 for r in results if r.get("overall_status") == "pass")
failed = len(results) - passed
payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "total": len(results),
    "passed": passed,
    "failed": failed,
    "results": results,
}
(out_dir / "chaos_summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

lines = [
    "# Chaos Suite Summary",
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
(out_dir / "chaos_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

strict_flag=()
if [[ "$STRICT" == "true" ]]; then
  strict_flag=(--strict)
fi

if "$PYTHON_BIN" "$ROOT_DIR/dev_tools/sandbox/chaos_tests/enforce_thresholds.py" \
  --chaos-dir "$OUT_DIR" \
  --thresholds "$ROOT_DIR/dev_tools/chaos/chaos_thresholds.json" \
  --output "$OUT_DIR/chaos_violations.json" \
  "${strict_flag[@]}"; then
  echo "[PASS] chaos_thresholds"
  ((pass_count+=1))
else
  echo "[FAIL] chaos_thresholds"
  if [[ -f "$OUT_DIR/chaos_violations.json" ]]; then
    echo "::group::chaos_violations.json"
    cat "$OUT_DIR/chaos_violations.json" || true
    echo "::endgroup::"
  fi
  ((fail_count+=1))
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

echo "Chaos suite complete. Summary: $summary_json"
