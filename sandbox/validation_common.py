"""Shared helpers for chaos, benchmark, and leak validation harnesses."""

from __future__ import annotations

import json
import os
import shlex
import subprocess  # nosec B404 - controlled command execution
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Sequence


@dataclass
class StepResult:
    name: str
    status: str
    duration_ms: float
    detail: str
    command: str | None = None
    output: str | None = None


@dataclass
class HarnessResult:
    harness: str
    started_at: str
    finished_at: str
    overall_status: str
    steps: list[StepResult]
    metrics: dict[str, Any]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_dir(path: str | Path) -> Path:
    output = Path(path)
    output.mkdir(parents=True, exist_ok=True)
    return output


def write_json(path: str | Path, payload: Any) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return target


def write_markdown(path: str | Path, content: str) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return target


def write_html(path: str | Path, title: str, body_html: str) -> Path:
    html = (
        "<!doctype html>\n"
        "<html lang=\"en\">\n"
        "<head><meta charset=\"utf-8\"><title>" + title + "</title>"
        "<style>body{font-family:Arial,sans-serif;margin:24px;}"
        "table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ccc;padding:8px;text-align:left;}"
        "th{background:#f5f5f5;} .ok{color:#0a7f00;} .fail{color:#b10000;} .warn{color:#9a6b00;}</style>"
        "</head><body>"
        f"<h1>{title}</h1>{body_html}</body></html>"
    )
    return write_markdown(path, html)


def bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def run_command(
    command: Sequence[str],
    *,
    timeout_seconds: int = 10,
    dry_run: bool = False,
    env: dict[str, str] | None = None,
    cwd: str | None = None,
) -> StepResult:
    started = time.monotonic()
    command_str = " ".join(shlex.quote(part) for part in command)
    if dry_run:
        return StepResult(
            name="command",
            status="simulated",
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail="dry-run",
            command=command_str,
            output="",
        )

    try:
        proc = subprocess.run(  # nosec B603
            list(command),
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
            env=env,
            cwd=cwd,
        )
        status = "ok" if proc.returncode == 0 else "failed"
        output = (proc.stdout + "\n" + proc.stderr).strip()
        return StepResult(
            name="command",
            status=status,
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=f"exit_code={proc.returncode}",
            command=command_str,
            output=output[:4000],
        )
    except subprocess.TimeoutExpired as exc:
        return StepResult(
            name="command",
            status="failed",
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=f"timeout_after={timeout_seconds}s",
            command=command_str,
            output=str(exc),
        )


def summarize_steps(steps: Iterable[StepResult]) -> dict[str, int]:
    totals = {"ok": 0, "failed": 0, "simulated": 0}
    for step in steps:
        key = step.status if step.status in totals else "failed"
        totals[key] += 1
    return totals


def harness_to_dict(result: HarnessResult) -> dict[str, Any]:
    return {
        "harness": result.harness,
        "started_at": result.started_at,
        "finished_at": result.finished_at,
        "overall_status": result.overall_status,
        "steps": [asdict(step) for step in result.steps],
        "metrics": result.metrics,
    }
