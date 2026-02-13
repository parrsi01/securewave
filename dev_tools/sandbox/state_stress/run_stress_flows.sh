#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_DIR="$ROOT_DIR/securewave_app"
OUT_DIR="${STATE_STRESS_OUTPUT_DIR:-$ROOT_DIR/artifacts/state_stress}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="${STATE_STRESS_TEST_TARGET:-test/state_machine/state_machine_stress_cycles_test.dart}"

mkdir -p "$OUT_DIR"
RAW_LOG="$OUT_DIR/stress_machine.log"
SUMMARY_JSON="$OUT_DIR/stress_summary.json"
SUMMARY_MD="$OUT_DIR/stress_summary.md"

pushd "$APP_DIR" >/dev/null

"$FLUTTER_BIN" pub get >/dev/null

set +e
"$FLUTTER_BIN" test "$TEST_TARGET" --machine 2>&1 | tee "$RAW_LOG"
test_exit="${PIPESTATUS[0]}"
set -e

popd >/dev/null

export STRESS_RAW_LOG="$RAW_LOG"
export STRESS_SUMMARY_JSON="$SUMMARY_JSON"
export STRESS_SUMMARY_MD="$SUMMARY_MD"
export STRESS_TEST_TARGET="$TEST_TARGET"
export STRESS_EXIT_CODE="$test_exit"

python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

raw_log = Path(os.environ["STRESS_RAW_LOG"])
summary_json = Path(os.environ["STRESS_SUMMARY_JSON"])
summary_md = Path(os.environ["STRESS_SUMMARY_MD"])
test_target = os.environ["STRESS_TEST_TARGET"]
exit_code = int(os.environ["STRESS_EXIT_CODE"])

lines = raw_log.read_text(encoding="utf-8", errors="replace").splitlines()
events = []
for line in lines:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        continue

test_started = 0
test_done = 0
test_failed = 0
duration_ms = 0
for event in events:
    event_type = event.get("type")
    if event_type == "testStart":
        test_started += 1
    elif event_type == "testDone":
        test_done += 1
        if event.get("result") == "failure":
            test_failed += 1
    elif event_type == "done":
        duration_ms = int(event.get("time", 0) or 0)

test_passed = max(0, test_done - test_failed)
overall = "pass" if exit_code == 0 and test_failed == 0 and test_done > 0 else "fail"

summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "target": test_target,
    "overall_status": overall,
    "exit_code": exit_code,
    "tests_started": test_started,
    "tests_completed": test_done,
    "tests_passed": test_passed,
    "tests_failed": test_failed,
    "duration_ms": duration_ms,
    "raw_log": str(raw_log),
}

summary_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

md_lines = [
    "# VPN State Stress Summary",
    "",
    f"- Generated: `{summary['generated_at']}`",
    f"- Target: `{test_target}`",
    f"- Status: **{overall}**",
    f"- Exit code: `{exit_code}`",
    f"- Tests started: **{test_started}**",
    f"- Tests completed: **{test_done}**",
    f"- Tests passed: **{test_passed}**",
    f"- Tests failed: **{test_failed}**",
    f"- Duration (ms): **{duration_ms}**",
    f"- Raw machine log: `{raw_log}`",
]
summary_md.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
PY

if [[ "$test_exit" -ne 0 ]]; then
  echo "[FAIL] state stress flows"
  exit 1
fi

echo "[PASS] state stress flows"
echo "summary: $SUMMARY_JSON"
