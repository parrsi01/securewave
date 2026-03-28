#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from dev_tools.local_agents.marlxgb_sandbox_agent import MarlXgbSandboxAgent, MarlXgbSandboxConfig
from dev_tools.local_agents.run_securewave_vpn_agents import _build_fault_config, _build_recovery_config
from dev_tools.local_agents.vpn_fault_lab_agent import FaultLabAgent
from dev_tools.local_agents.vpn_recovery_ml_agent import RecoveryMlAgent


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the local MARL/XGBoost sandbox VPN agent")
    parser.add_argument("--cycles", type=int, default=1, help="How many cycles to run (0 means forever)")
    parser.add_argument("--interval-seconds", type=float, default=60.0)
    parser.add_argument("--api-base-url", default="https://138.199.204.139.nip.io/api")
    parser.add_argument("--interface", default="sw-wg")
    parser.add_argument("--output-dir", default="artifacts/local_agents/runtime/marlxgb_sandbox")
    parser.add_argument("--publish-path", default="static/data/performance_benchmarks.json")
    parser.add_argument("--diagnostics-dir", default="vpn_diagnostics")
    parser.add_argument("--disable-network-drop", action="store_true")
    parser.add_argument("--disable-live-faults", action="store_true")
    parser.add_argument("--execute-destructive", action="store_true")
    parser.add_argument("--execute-recovery", action="store_true")
    parser.add_argument("--allow-vpn-bounce", action="store_true")
    parser.add_argument("--preferred-wifi-connection", default=None)
    parser.add_argument("--min-training-records", type=int, default=10)
    parser.add_argument("--patch-threshold", type=int, default=3)
    parser.add_argument("--download-url", default=os.getenv("SECUREWAVE_BENCHMARK_DOWNLOAD_URL", "https://cachefly.cachefly.net/10mb.test"))
    parser.add_argument("--ping-target", default=os.getenv("SECUREWAVE_BENCHMARK_PING_TARGET", "1.1.1.1"))
    parser.add_argument("--bytes", type=int, default=5 * 1024 * 1024)
    parser.add_argument("--iperf-host", default=os.getenv("BENCHMARK_IPERF_HOST", ""))
    parser.add_argument("--iperf-port", type=int, default=int(os.getenv("BENCHMARK_IPERF_PORT", "5201")))
    parser.add_argument("--iperf-duration", type=int, default=int(os.getenv("BENCHMARK_IPERF_DURATION", "8")))
    parser.add_argument("--wg-interface", default=os.getenv("SECUREWAVE_WG_INTERFACE", ""))
    parser.add_argument("--openvpn-interface", default=os.getenv("SECUREWAVE_OPENVPN_INTERFACE", ""))
    parser.add_argument("--ikev2-interface", default=os.getenv("SECUREWAVE_IKEV2_INTERFACE", ""))
    args = parser.parse_args()

    fault_agent = FaultLabAgent(_build_fault_config(args))
    recovery_agent = RecoveryMlAgent(_build_recovery_config(args))
    agent = MarlXgbSandboxAgent(
        config=MarlXgbSandboxConfig(
            output_dir=Path(args.output_dir),
            publish_path=Path(args.publish_path),
            download_url=args.download_url,
            ping_target=args.ping_target,
            bytes_to_fetch=max(1, args.bytes),
            iperf_host=args.iperf_host.strip() or None,
            iperf_port=args.iperf_port,
            iperf_duration=max(1, args.iperf_duration),
            wg_interface=args.wg_interface.strip() or None,
            openvpn_interface=args.openvpn_interface.strip() or None,
            ikev2_interface=args.ikev2_interface.strip() or None,
        ),
        fault_agent=fault_agent,
        recovery_agent=recovery_agent,
    )

    cycle = 0
    while args.cycles == 0 or cycle < args.cycles:
        cycle += 1
        payload = agent.run_cycle(cycle=cycle)
        print(json.dumps(payload, indent=2))
        if args.cycles != 0 and cycle >= args.cycles:
            break
        time.sleep(max(1.0, args.interval_seconds))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
