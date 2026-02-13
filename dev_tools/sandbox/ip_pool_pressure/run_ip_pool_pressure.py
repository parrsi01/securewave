#!/usr/bin/env python3
"""
IP pool pressure harness (500 peers with churn + reclaim).

Outputs:
- artifacts/ip_pool_pressure/report.json
- artifacts/ip_pool_pressure/summary.csv
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.ip_pool_pressure.simulator import IPPoolPressureConfig, simulate_ip_pool_pressure


def main() -> int:
    parser = argparse.ArgumentParser(description="Run IP pool pressure simulation")
    parser.add_argument("--output-dir", default="artifacts/ip_pool_pressure")
    parser.add_argument("--peers", type=int, default=500)
    parser.add_argument("--cycles", type=int, default=10)
    parser.add_argument("--churn", type=int, default=50)
    parser.add_argument("--reserved-hosts", type=int, default=510)
    parser.add_argument("--max-blocks", type=int, default=1)
    parser.add_argument("--base-cidr", default="10.250.0.0/22")
    parser.add_argument("--alert-threshold-pct", type=int, default=90)
    args = parser.parse_args()

    cfg = IPPoolPressureConfig(
        peers=max(1, args.peers),
        cycles=max(1, args.cycles),
        churn_per_cycle=max(0, args.churn),
        base_cidr=str(args.base_cidr),
        max_blocks=max(1, args.max_blocks),
        reserved_hosts=max(2, args.reserved_hosts),
        alert_threshold_pct=max(50, min(99, args.alert_threshold_pct)),
    )

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    report = simulate_ip_pool_pressure(cfg=cfg, output_dir=out_dir)
    print(json.dumps(report.get("summary", {}), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
