from __future__ import annotations

import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable

from dev_tools.local_agents.common import (
    ARTIFACTS_ROOT,
    DATA_ROOT,
    ConnectivitySnapshot,
    append_csv_row,
    append_jsonl,
    collect_connectivity_snapshot,
    derive_bandwidth_mbps,
    ensure_dir,
    load_json,
    write_json,
)
from dev_tools.sandbox.chaos_tests.network_drop import run_harness as run_network_drop_harness
from dev_tools.sandbox.live_validation.network_failure_cases import run_fault_cases
from services.xgb_qos import QoSInput, XGBQoSClassifier
from services.xgb_risk import RiskInput, XGBRiskScorer


TelemetryCollector = Callable[..., ConnectivitySnapshot]


TELEMETRY_FIELDNAMES = [
    "timestamp",
    "user_id",
    "server_id",
    "latency_ms",
    "packet_loss",
    "jitter_ms",
    "bandwidth_mbps",
    "connection_stability",
    "disconnect_count",
    "session_duration_minutes",
    "qos_label",
    "risk_score",
]


@dataclass
class FaultLabConfig:
    api_base_url: str = os.getenv("SECUREWAVE_AGENT_API_BASE_URL", "https://138.199.204.139.nip.io/api")
    interface: str = os.getenv("SECUREWAVE_AGENT_VPN_INTERFACE", "sw-wg")
    output_dir: Path = field(default_factory=lambda: ARTIFACTS_ROOT / "vpn_fault_lab")
    telemetry_path: Path = field(default_factory=lambda: DATA_ROOT / "vpn_fault_lab_telemetry.csv")
    events_path: Path = field(default_factory=lambda: ARTIFACTS_ROOT / "vpn_fault_lab" / "fault_lab_events.jsonl")
    state_path: Path = field(default_factory=lambda: ARTIFACTS_ROOT / "vpn_fault_lab" / "fault_lab_state.json")
    qos_model_path: Path = field(default_factory=lambda: DATA_ROOT / "models" / "local_agent_qos.json")
    risk_model_path: Path = field(default_factory=lambda: DATA_ROOT / "models" / "local_agent_risk.json")
    run_network_drop: bool = True
    run_live_network_faults: bool = True
    execute_destructive: bool = False
    stable_window: int = 8


class FaultLabAgent:
    def __init__(
        self,
        config: FaultLabConfig | None = None,
        *,
        collector: TelemetryCollector = collect_connectivity_snapshot,
    ) -> None:
        self.config = config or FaultLabConfig()
        self.collector = collector
        ensure_dir(self.config.output_dir)
        ensure_dir(self.config.telemetry_path.parent)
        self._qos = XGBQoSClassifier(model_path=str(self.config.qos_model_path))
        self._risk = XGBRiskScorer(model_path=str(self.config.risk_model_path))

    def _load_state(self) -> dict[str, Any]:
        return load_json(
            self.config.state_path,
            default={
                "started_at": time.time(),
                "cycle_count": 0,
                "disconnect_count": 0,
                "recent_online": [],
                "recent_latencies": [],
                "last_snapshot_timestamp": time.time(),
                "last_rx_bytes": None,
                "last_tx_bytes": None,
            },
        )

    def _save_state(self, state: dict[str, Any]) -> None:
        write_json(self.config.state_path, state)

    def _simulate_faults(self) -> list[dict[str, Any]]:
        scenarios: list[dict[str, Any]] = []
        if self.config.run_network_drop:
            payload = run_network_drop_harness(
                output_dir=self.config.output_dir / "network_drop",
                interface=self.config.interface,
                execute=self.config.execute_destructive,
            )
            scenarios.append(
                {
                    "harness": "network_drop",
                    "overall_status": payload.get("overall_status", "unknown"),
                    "metrics": payload.get("metrics", {}),
                }
            )
        if self.config.run_live_network_faults and self.config.api_base_url:
            payload = run_fault_cases(
                output_dir=self.config.output_dir / "network_failure_cases",
                api_base_url=self.config.api_base_url,
                interface=self.config.interface,
                execute=self.config.execute_destructive,
                strict=False,
            )
            scenarios.append(
                {
                    "harness": "network_failure_cases",
                    "overall_status": payload.get("overall_status", "unknown"),
                    "scenario_count": len(payload.get("scenarios", [])),
                }
            )
        return scenarios

    def _connection_stability(self, state: dict[str, Any], online_now: bool) -> float:
        window = list(state.get("recent_online", []))
        window.append(1 if online_now else 0)
        window = window[-self.config.stable_window :]
        state["recent_online"] = window
        if not window:
            return 0.0
        return round(sum(window) / len(window), 3)

    def _estimate_jitter(self, state: dict[str, Any], latency_ms: float) -> float:
        latencies = list(state.get("recent_latencies", []))
        latencies.append(latency_ms)
        latencies = latencies[-self.config.stable_window :]
        state["recent_latencies"] = latencies
        if len(latencies) < 2:
            return 0.0
        avg = sum(latencies) / len(latencies)
        return round(abs(latency_ms - avg), 3)

    def _packet_loss(self, snapshot: ConnectivitySnapshot) -> float:
        if not snapshot.internet_reachable:
            return 1.0
        if snapshot.internet_reachable and not snapshot.api_health_ok:
            return 0.25
        return 0.0

    def _risk_input(self, snapshot: ConnectivitySnapshot, disconnect_count: int) -> RiskInput:
        reconnect_frequency = min(20, disconnect_count)
        return RiskInput(
            login_failures=0,
            reconnect_frequency=reconnect_frequency,
            unusual_hours=False,
            ip_reputation=1.0 if snapshot.internet_reachable else 0.4,
            geo_anomaly=False,
            data_exfil_indicator=0.0,
            session_duration_anomaly=0.0,
        )

    def run_cycle(self) -> dict[str, Any]:
        state = self._load_state()
        pre = self.collector(api_base_url=self.config.api_base_url, interface=self.config.interface)
        scenarios = self._simulate_faults()
        post = self.collector(
            api_base_url=self.config.api_base_url,
            interface=self.config.interface,
            extra_notes=[f"scenario:{item['harness']}:{item['overall_status']}" for item in scenarios],
        )

        prev_ts = float(state.get("last_snapshot_timestamp", time.time()))
        now_ts = time.time()
        elapsed = max(1.0, now_ts - prev_ts)

        bandwidth_mbps = derive_bandwidth_mbps(
            previous_rx_bytes=state.get("last_rx_bytes"),
            previous_tx_bytes=state.get("last_tx_bytes"),
            current_rx_bytes=post.rx_bytes,
            current_tx_bytes=post.tx_bytes,
            elapsed_seconds=elapsed,
        )
        latency_ms = float(post.api_latency_ms or (900.0 if not post.internet_reachable else 120.0))
        packet_loss = self._packet_loss(post)
        jitter_ms = self._estimate_jitter(state, latency_ms)

        online_now = bool(post.internet_reachable and post.default_route_present)
        connection_stability = self._connection_stability(state, online_now)

        incident = int(post.vpn_interface_up and not post.internet_reachable)
        disconnect_count = int(state.get("disconnect_count", 0)) + incident
        state["disconnect_count"] = disconnect_count
        state["cycle_count"] = int(state.get("cycle_count", 0)) + 1
        state["last_snapshot_timestamp"] = now_ts
        state["last_rx_bytes"] = post.rx_bytes
        state["last_tx_bytes"] = post.tx_bytes

        qos_result = self._qos.predict(
            QoSInput(
                latency_ms=latency_ms,
                packet_loss=packet_loss,
                jitter_ms=jitter_ms,
                bandwidth_mbps=bandwidth_mbps,
                connection_stability=connection_stability,
            )
        )
        risk_result = self._risk.predict(self._risk_input(post, disconnect_count))

        session_duration_minutes = round((now_ts - float(state.get("started_at", now_ts))) / 60.0, 3)
        telemetry_row = {
            "timestamp": post.timestamp,
            "user_id": 0,
            "server_id": self.config.interface,
            "latency_ms": round(latency_ms, 3),
            "packet_loss": round(packet_loss, 3),
            "jitter_ms": round(jitter_ms, 3),
            "bandwidth_mbps": round(bandwidth_mbps, 3),
            "connection_stability": connection_stability,
            "disconnect_count": disconnect_count,
            "session_duration_minutes": session_duration_minutes,
            "qos_label": qos_result.label,
            "risk_score": round(risk_result.score, 3),
        }
        append_csv_row(self.config.telemetry_path, TELEMETRY_FIELDNAMES, telemetry_row)

        event_payload = {
            "event": "fault_lab_cycle",
            "pre": pre.to_dict(),
            "post": post.to_dict(),
            "scenarios": scenarios,
            "telemetry": telemetry_row,
            "qos": asdict(qos_result),
            "risk": asdict(risk_result),
        }
        append_jsonl(self.config.events_path, event_payload)
        self._save_state(state)
        return event_payload
