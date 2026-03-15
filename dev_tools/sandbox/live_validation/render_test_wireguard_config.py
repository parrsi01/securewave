#!/usr/bin/env python3
"""Render a temporary WireGuard config for validation/stability testing."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import build_wireguard_test_config


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a temporary WireGuard test profile")
    parser.add_argument("--input", required=True, help="Source wg-quick config path")
    parser.add_argument("--output", required=True, help="Rendered config path")
    parser.add_argument("--api-base-url", required=True, help="Flutter client API base URL")
    parser.add_argument("--split-tunnel", action="store_true", help="Replace full-tunnel AllowedIPs for testing")
    parser.add_argument(
        "--split-tunnel-allowed-ips",
        default="10.0.0.0/8,172.16.0.0/12",
        help="Comma-separated AllowedIPs used with --split-tunnel",
    )
    args = parser.parse_args()

    source = Path(args.input)
    output = Path(args.output)
    raw = source.read_text(encoding="utf-8")
    rendered, meta = build_wireguard_test_config(
        raw,
        api_base_url=args.api_base_url,
        enable_split_tunnel=bool(args.split_tunnel),
        split_tunnel_allowed_ips=[
            item.strip()
            for item in str(args.split_tunnel_allowed_ips).split(",")
            if item.strip()
        ],
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
