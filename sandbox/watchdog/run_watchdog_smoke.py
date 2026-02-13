#!/usr/bin/env python3
"""
Smoke-run the TunnelWatchdog to produce a minimal JSONL artifact.

This does not require a live WireGuard server. It writes:
- artifacts/watchdog/watchdog_events.jsonl
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _set_default_env() -> None:
    # Ensure we don't accidentally point at a real DB or require prod-only config.
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("TESTING", "true")
    os.environ.setdefault("DEMO_MODE", "true")
    os.environ.setdefault("WG_MOCK_MODE", "true")
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

    # Watchdog settings (min interval is enforced by the implementation).
    os.environ.setdefault("SECUREWAVE_WATCHDOG_ENABLED", "true")
    os.environ.setdefault("SECUREWAVE_WATCHDOG_INTERVAL_SECONDS", "5")


async def _run(duration_seconds: float, events_path: Path) -> None:
    os.environ["SECUREWAVE_WATCHDOG_EVENTS_PATH"] = str(events_path)
    events_path.parent.mkdir(parents=True, exist_ok=True)
    events_path.write_text("", encoding="utf-8")

    # Import after env is set so database/session binds to the intended DB.
    from database.session import create_tables
    create_tables()

    from services.tunnel_watchdog import get_tunnel_watchdog

    watchdog = get_tunnel_watchdog()
    task = asyncio.create_task(watchdog.start())
    try:
        await asyncio.sleep(max(0.1, duration_seconds))
    finally:
        await watchdog.stop()
        await task


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the tunnel watchdog briefly and write artifacts.")
    parser.add_argument("--duration-seconds", type=float, default=6.0)
    parser.add_argument("--events-path", default="artifacts/watchdog/watchdog_events.jsonl")
    args = parser.parse_args()

    _set_default_env()
    asyncio.run(_run(duration_seconds=float(args.duration_seconds), events_path=Path(args.events_path)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
