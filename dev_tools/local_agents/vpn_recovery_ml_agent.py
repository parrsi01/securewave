from __future__ import annotations

import csv
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from dev_tools.local_agents.common import (
    ARTIFACTS_ROOT,
    DATA_ROOT,
    CommandResult,
    ConnectivitySnapshot,
    append_jsonl,
    collect_connectivity_snapshot,
    command_exists,
    preferred_wifi_connection_name,
    read_recent_jsonl,
    run_command,
    utc_now_iso,
    write_json,
)
from ml.data import build_qos_dataset, build_risk_dataset
from services.marl_policy import StateVector, create_policy_engine
from services.xgb_qos import QoSInput, XGBQoSClassifier
from services.xgb_risk import RiskInput, XGBRiskScorer


SnapshotCollector = Callable[..., ConnectivitySnapshot]
CommandRunner = Callable[..., CommandResult]


@dataclass
class RecoveryMlConfig:
    api_base_url: str = os.getenv("SECUREWAVE_AGENT_API_BASE_URL", "https://138.199.204.139.nip.io/api")
    interface: str = os.getenv("SECUREWAVE_AGENT_VPN_INTERFACE", "sw-wg")
    telemetry_path: Path = field(default_factory=lambda: DATA_ROOT / "vpn_fault_lab_telemetry.csv")
    events_path: Path = field(default_factory=lambda: ARTIFACTS_ROOT / "vpn_fault_lab" / "fault_lab_events.jsonl")
    output_dir: Path = field(default_factory=lambda: ARTIFACTS_ROOT / "vpn_recovery_ml")
    qos_model_path: Path = field(default_factory=lambda: DATA_ROOT / "models" / "local_agent_qos.json")
    risk_model_path: Path = field(default_factory=lambda: DATA_ROOT / "models" / "local_agent_risk.json")
    execute_recovery: bool = False
    allow_vpn_bounce: bool = False
    preferred_wifi_connection: str | None = os.getenv("SECUREWAVE_AGENT_WIFI_CONNECTION")
    min_training_records: int = 10
    patch_threshold: int = 3


class RecoveryMlAgent:
    def __init__(
        self,
        config: RecoveryMlConfig | None = None,
        *,
        collector: SnapshotCollector = collect_connectivity_snapshot,
        command_runner: CommandRunner = run_command,
    ) -> None:
        self.config = config or RecoveryMlConfig()
        self.collector = collector
        self.command_runner = command_runner
        self.config.output_dir.mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _parse_float(value: Any, *, default: float = 0.0) -> float:
        try:
            if value in (None, ""):
                return default
            return float(value)
        except (TypeError, ValueError):
            return default

    @classmethod
    def _parse_int(cls, value: Any, *, default: int = 0) -> int:
        try:
            if value in (None, ""):
                return default
            return int(float(value))
        except (TypeError, ValueError):
            return default

    def _load_records(self) -> list[dict[str, Any]]:
        if not self.config.telemetry_path.exists():
            return []
        records: list[dict[str, Any]] = []
        with self.config.telemetry_path.open("r", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                records.append(
                    {
                        "timestamp": row.get("timestamp", ""),
                        "user_id": self._parse_int(row.get("user_id"), default=0),
                        "server_id": row.get("server_id", self.config.interface),
                        "latency_ms": self._parse_float(row.get("latency_ms"), default=0.0),
                        "packet_loss": self._parse_float(row.get("packet_loss"), default=0.0),
                        "jitter_ms": self._parse_float(row.get("jitter_ms"), default=0.0),
                        "bandwidth_mbps": self._parse_float(row.get("bandwidth_mbps"), default=0.0),
                        "connection_stability": self._parse_float(
                            row.get("connection_stability"),
                            default=0.0,
                        ),
                        "disconnect_count": self._parse_int(
                            row.get("disconnect_count"),
                            default=0,
                        ),
                        "session_duration_minutes": self._parse_int(
                            row.get("session_duration_minutes"),
                            default=0,
                        ),
                        "qos_label": row.get("qos_label", "poor"),
                        "risk_score": self._parse_float(row.get("risk_score"), default=0.0),
                    }
                )
        return records

    def _train_models(self, records: list[dict[str, Any]]) -> dict[str, Any]:
        summary = {"trained": False, "ml_mode": "unavailable", "record_count": len(records)}
        if len(records) < self.config.min_training_records:
            return summary

        qos = XGBQoSClassifier(model_path=None)
        risk = XGBRiskScorer(model_path=None)
        summary["ml_mode"] = (
            "marl_xgb"
            if qos.use_ml and risk.use_ml
            else "marl_rule_fallback"
        )

        x_qos, y_qos = build_qos_dataset(records)
        x_risk, y_risk = build_risk_dataset(records)
        if qos.use_ml and x_qos and y_qos:
            qos.train(x_qos, y_qos)
            qos.save_model(str(self.config.qos_model_path))
            summary["qos_model_path"] = str(self.config.qos_model_path)
        if risk.use_ml and x_risk and y_risk:
            risk.train(x_risk, y_risk)
            risk.save_model(str(self.config.risk_model_path))
            summary["risk_model_path"] = str(self.config.risk_model_path)
        summary["trained"] = True
        return summary

    def _latest_snapshot(self) -> dict[str, Any] | None:
        recent = read_recent_jsonl(self.config.events_path, limit=1)
        return recent[-1] if recent else None

    def _state_vector(self, record: dict[str, Any]) -> StateVector:
        reconnect_count = int(record.get("disconnect_count", 0))
        latency_ms = float(record.get("latency_ms", 100.0))
        packet_loss = float(record.get("packet_loss", 0.0))
        jitter_ms = float(record.get("jitter_ms", 0.0))
        connection_duration_minutes = float(record.get("session_duration_minutes", 0.0))
        qos_classifier = XGBQoSClassifier(model_path=str(self.config.qos_model_path))
        risk_scorer = XGBRiskScorer(model_path=str(self.config.risk_model_path))
        qos_result = qos_classifier.predict(
            QoSInput(
                latency_ms=latency_ms,
                packet_loss=packet_loss,
                jitter_ms=jitter_ms,
                bandwidth_mbps=float(record.get("bandwidth_mbps", 0.0)),
                connection_stability=float(record.get("connection_stability", 0.0)),
            )
        )
        risk_result = risk_scorer.predict(
            RiskInput(
                login_failures=0,
                reconnect_frequency=reconnect_count,
                unusual_hours=False,
                ip_reputation=1.0 if packet_loss < 1.0 else 0.4,
                geo_anomaly=False,
                data_exfil_indicator=0.0,
                session_duration_anomaly=0.0,
            )
        )
        return StateVector(
            user_id=int(record.get("user_id", 0)),
            server_id=str(record.get("server_id", self.config.interface)),
            qos_score=qos_result.score,
            risk_score=risk_result.score,
            server_load=min(1.0, float(record.get("bandwidth_mbps", 0.0)) / 100.0),
            latency_ms=latency_ms,
            packet_loss=packet_loss,
            jitter_ms=jitter_ms,
            connection_duration_minutes=connection_duration_minutes,
            reconnect_count=reconnect_count,
            throughput_mbps=float(record.get("bandwidth_mbps", 0.0)),
        )

    def _plan_recovery(self, snapshot: ConnectivitySnapshot, state: StateVector) -> list[dict[str, Any]]:
        actions: list[dict[str, Any]] = []
        policy = create_policy_engine()
        decision = policy.decide(state)
        actions.append(
            {
                "name": "policy_decision",
                "decision": decision.action.value,
                "reason": decision.reason,
                "confidence": decision.confidence,
            }
        )

        if snapshot.internet_reachable:
            return actions

        if snapshot.wifi_radio_enabled is False and command_exists("nmcli"):
            actions.append(
                {
                    "name": "enable_wifi_radio",
                    "command": ["nmcli", "radio", "wifi", "on"],
                }
            )

        preferred = self.config.preferred_wifi_connection or preferred_wifi_connection_name()
        if (
            command_exists("nmcli")
            and not snapshot.wifi_connected
            and preferred
        ):
            actions.append(
                {
                    "name": "activate_wifi_connection",
                    "command": ["nmcli", "connection", "up", preferred],
                }
            )

        if command_exists("nmcli") and not snapshot.default_route_present:
            actions.append(
                {
                    "name": "reenable_networking",
                    "command": ["nmcli", "networking", "on"],
                }
            )

        if (
            self.config.allow_vpn_bounce
            and snapshot.vpn_interface_up
            and command_exists("ip")
        ):
            actions.append(
                {
                    "name": "bounce_vpn_interface_down",
                    "command": ["ip", "link", "set", self.config.interface, "down"],
                }
            )
            actions.append(
                {
                    "name": "bounce_vpn_interface_up",
                    "command": ["ip", "link", "set", self.config.interface, "up"],
                }
            )

        return actions

    def _execute_actions(self, actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for action in actions:
            if "command" not in action:
                results.append({**action, "executed": False, "ok": True})
                continue
            if not self.config.execute_recovery:
                results.append({**action, "executed": False, "ok": True, "detail": "dry_run"})
                continue
            result = self.command_runner(action["command"], timeout_seconds=12.0)
            results.append(
                {
                    **action,
                    "executed": True,
                    "ok": result.ok,
                    "returncode": result.returncode,
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                }
            )
        return results

    def _write_patch_recommendations(self, recent_events: list[dict[str, Any]]) -> dict[str, Any]:
        repeated_offline_with_vpn = 0
        repeated_wifi_disabled = 0
        for event in recent_events:
            post = event.get("post", {})
            if post.get("vpn_interface_up") and not post.get("internet_reachable"):
                repeated_offline_with_vpn += 1
            if post.get("wifi_radio_enabled") is False:
                repeated_wifi_disabled += 1

        recommendations: list[dict[str, Any]] = []
        if repeated_offline_with_vpn >= self.config.patch_threshold:
            recommendations.append(
                {
                    "signature": "internet_down_while_vpn_interface_up",
                    "files": [
                        "securewave_app/lib/core/state/vpn_state.dart",
                        "static/linux/runner/my_application.cc",
                    ],
                    "recommendation": (
                        "Capture and restore the host default route deterministically on connect/disconnect, "
                        "and audit Linux runner teardown so the VM never remains online=false with sw-wg still present."
                    ),
                }
            )
        if repeated_wifi_disabled >= self.config.patch_threshold:
            recommendations.append(
                {
                    "signature": "wifi_radio_disabled_during_recovery",
                    "files": [
                        "static/linux/runner/my_application.cc",
                    ],
                    "recommendation": (
                        "Add explicit NetworkManager Wi-Fi fallback/restore handling after WireGuard teardown "
                        "so VM recovery is not dependent on manual radio re-enable."
                    ),
                }
            )

        payload = {
            "generated_at": utc_now_iso(),
            "recommendations": recommendations,
            "repeated_offline_with_vpn": repeated_offline_with_vpn,
            "repeated_wifi_disabled": repeated_wifi_disabled,
        }
        write_json(self.config.output_dir / "patch_recommendations.json", payload)

        md_lines = [
            "# Local VPN Patch Recommendations",
            "",
            f"- Generated: `{payload['generated_at']}`",
            f"- Offline-with-VPN count: `{repeated_offline_with_vpn}`",
            f"- Wi-Fi-disabled count: `{repeated_wifi_disabled}`",
            "",
        ]
        if not recommendations:
            md_lines.append("- No repeated local signatures crossed the patch threshold.")
        else:
            for item in recommendations:
                md_lines.append(f"## {item['signature']}")
                md_lines.append("")
                md_lines.append(f"- Files: `{', '.join(item['files'])}`")
                md_lines.append(f"- Recommendation: {item['recommendation']}")
                md_lines.append("")
        (self.config.output_dir / "patch_recommendations.md").write_text(
            "\n".join(md_lines) + "\n",
            encoding="utf-8",
        )
        return payload

    def run_cycle(self) -> dict[str, Any]:
        records = self._load_records()
        training = self._train_models(records)
        latest_record = records[-1] if records else None
        snapshot = self.collector(api_base_url=self.config.api_base_url, interface=self.config.interface)
        if latest_record is None:
            payload = {
                "generated_at": utc_now_iso(),
                "training": training,
                "snapshot": snapshot.to_dict(),
                "actions": [],
                "note": "no_telemetry_records",
            }
            append_jsonl(self.config.output_dir / "recovery_events.jsonl", payload)
            write_json(self.config.output_dir / "latest_recovery_cycle.json", payload)
            return payload

        state = self._state_vector(latest_record)
        actions = self._plan_recovery(snapshot, state)
        executed = self._execute_actions(actions)
        validation = self.collector(
            api_base_url=self.config.api_base_url,
            interface=self.config.interface,
            extra_notes=["recovery_validation"],
        )

        recent_events = read_recent_jsonl(self.config.events_path, limit=25)
        patch_plan = self._write_patch_recommendations(recent_events)

        payload = {
            "generated_at": utc_now_iso(),
            "training": training,
            "latest_record": latest_record,
            "snapshot_before": snapshot.to_dict(),
            "actions": executed,
            "snapshot_after": validation.to_dict(),
            "patch_plan": patch_plan,
        }
        append_jsonl(self.config.output_dir / "recovery_events.jsonl", payload)
        write_json(self.config.output_dir / "latest_recovery_cycle.json", payload)
        return payload
