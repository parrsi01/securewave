#!/usr/bin/env python3
"""Dedicated MARL/XGBoost sandbox agent for isolated VPN validation."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

from dev_tools.local_agents.common import ensure_dir, utc_now_iso
from dev_tools.local_agents.vpn_fault_lab_agent import FaultLabAgent
from dev_tools.local_agents.vpn_recovery_ml_agent import RecoveryMlAgent
from dev_tools.sandbox.benchmark.live_protocol_benchmark import run_live_protocol_benchmark


@dataclass
class MarlXgbSandboxConfig:
    output_dir: Path
    publish_path: Path
    download_url: str
    ping_target: str
    bytes_to_fetch: int
    iperf_host: Optional[str]
    iperf_port: int
    iperf_duration: int
    wg_interface: Optional[str]
    openvpn_interface: Optional[str]
    ikev2_interface: Optional[str]


class MarlXgbSandboxAgent:
    def __init__(
        self,
        *,
        config: MarlXgbSandboxConfig,
        fault_agent: Optional[FaultLabAgent] = None,
        recovery_agent: Optional[RecoveryMlAgent] = None,
    ) -> None:
        self.config = config
        self.fault_agent = fault_agent
        self.recovery_agent = recovery_agent

    def run_cycle(self, *, cycle: int) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "captured_at": utc_now_iso(),
            "cycle": cycle,
        }
        if self.fault_agent is not None:
            payload["fault"] = self.fault_agent.run_cycle()
        if self.recovery_agent is not None:
            payload["recovery"] = self.recovery_agent.run_cycle()
        payload["benchmarks"] = run_live_protocol_benchmark(
            output_root=self.config.output_dir / "benchmarks",
            publish_path=self.config.publish_path,
            download_url=self.config.download_url,
            ping_target=self.config.ping_target,
            bytes_to_fetch=self.config.bytes_to_fetch,
            iperf_host=self.config.iperf_host,
            iperf_port=self.config.iperf_port,
            iperf_duration=self.config.iperf_duration,
            wg_interface=self.config.wg_interface,
            openvpn_interface=self.config.openvpn_interface,
            ikev2_interface=self.config.ikev2_interface,
        )
        ensure_dir(self.config.output_dir)
        (self.config.output_dir / "latest_cycle.json").write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )
        return payload
