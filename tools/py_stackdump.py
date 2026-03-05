#!/usr/bin/env python3
"""
Send stack dump signals to a running Python process (pytest).

Usage:
  tools/py_stackdump.py --pid <PID> [--asyncio]

Requires:
  - tests/conftest.py registering SIGUSR1 (faulthandler)
  - optional SIGUSR2 handler for asyncio task dumps
"""
from __future__ import annotations

import argparse
import os
import signal
import sys
import time


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Trigger Python stack dumps via signal.")
    parser.add_argument("--pid", type=int, required=True, help="Target process id (pytest)")
    parser.add_argument(
        "--asyncio",
        action="store_true",
        help="Also trigger asyncio task dump via SIGUSR2 (if registered).",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    pid = args.pid
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        print(f"pid {pid} not found", file=sys.stderr)
        return 2

    if not hasattr(signal, "SIGUSR1"):
        print("SIGUSR1 not supported on this platform", file=sys.stderr)
        return 2

    os.kill(pid, signal.SIGUSR1)
    time.sleep(0.2)
    if args.asyncio and hasattr(signal, "SIGUSR2"):
        os.kill(pid, signal.SIGUSR2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
