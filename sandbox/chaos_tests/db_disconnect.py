#!/usr/bin/env python3
"""Database outage/recovery chaos harness."""

from __future__ import annotations

import argparse
import os
import time
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sqlalchemy import create_engine, text

from sandbox.validation_common import (
    HarnessResult,
    StepResult,
    ensure_dir,
    harness_to_dict,
    summarize_steps,
    utc_now_iso,
    write_html,
    write_json,
    write_markdown,
)


def _probe_db(url: str, timeout_seconds: int = 4) -> tuple[bool, str, float]:
    started = time.monotonic()
    try:
        engine = create_engine(url, pool_pre_ping=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, "connection_ok", round((time.monotonic() - started) * 1000, 2)
    except Exception as exc:  # pragma: no cover - environment dependent
        return False, str(exc), round((time.monotonic() - started) * 1000, 2)


def run_harness(*, output_dir: Path, db_url: str, outage_url: str) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    ok_before, detail_before, ms_before = _probe_db(db_url)
    steps.append(StepResult(name="baseline_probe", status="ok" if ok_before else "failed", duration_ms=ms_before, detail=detail_before))

    ok_outage, detail_outage, ms_outage = _probe_db(outage_url)
    # Outage injection is considered successful when probe fails.
    outage_status = "ok" if not ok_outage else "failed"
    steps.append(
        StepResult(
            name="outage_injection",
            status=outage_status,
            duration_ms=ms_outage,
            detail="failure_observed" if outage_status == "ok" else "unexpected_connectivity",
            output=detail_outage[:4000],
        )
    )

    ok_recover, detail_recover, ms_recover = _probe_db(db_url)
    steps.append(
        StepResult(
            name="recovery_probe",
            status="ok" if ok_recover else "failed",
            duration_ms=ms_recover,
            detail=detail_recover[:4000],
        )
    )

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()

    result = HarnessResult(
        harness="db_disconnect",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "baseline_connected": ok_before,
            "outage_failure_observed": not ok_outage,
            "recovery_connected": ok_recover,
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "db_disconnect_result.json", payload)

    lines = [
        "# DB Disconnect Chaos Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- Baseline DB reachable: `{ok_before}`",
        f"- Outage simulated failure observed: `{not ok_outage}`",
        f"- Recovery DB reachable: `{ok_recover}`",
        "",
        "| Step | Status | Duration (ms) | Detail |",
        "|---|---|---:|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.duration_ms:.2f} | {step.detail} |")
    write_markdown(out_dir / "db_disconnect_summary.md", "\n".join(lines) + "\n")

    rows = "".join(
        f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.duration_ms:.2f}</td><td>{s.detail}</td></tr>" for s in steps
    )
    write_html(
        out_dir / "db_disconnect_summary.html",
        title="DB Disconnect Chaos Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Duration (ms)</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Simulate DB outage and recovery checks")
    parser.add_argument("--output-dir", default="artifacts/chaos_tests")
    parser.add_argument("--db-url", default=os.getenv("DATABASE_URL", "sqlite:////tmp/securewave_chaos.db"))
    parser.add_argument(
        "--outage-url",
        default=os.getenv("CHAOS_DB_OUTAGE_URL", "postgresql://invalid:invalid@127.0.0.1:1/unreachable"),
    )
    args = parser.parse_args()

    payload = run_harness(output_dir=Path(args.output_dir), db_url=args.db_url, outage_url=args.outage_url)
    print(payload["overall_status"])
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
