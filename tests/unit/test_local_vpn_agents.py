from __future__ import annotations

import csv
from pathlib import Path

from dev_tools.local_agents import run_securewave_vpn_agents
from dev_tools.local_agents.common import ConnectivitySnapshot
from dev_tools.local_agents.vpn_fault_lab_agent import FaultLabAgent, FaultLabConfig
from dev_tools.local_agents.vpn_recovery_ml_agent import RecoveryMlAgent, RecoveryMlConfig


def _snapshot(
    *,
    internet_reachable: bool,
    wifi_radio_enabled: bool | None = True,
    wifi_connected: bool | None = False,
    ethernet_connected: bool | None = False,
    vpn_interface_up: bool = True,
    default_route_present: bool = True,
    api_health_ok: bool = True,
    api_latency_ms: float | None = 42.0,
):
    return ConnectivitySnapshot(
        timestamp="2026-03-18T00:00:00Z",
        interface="sw-wg",
        vpn_interface_up=vpn_interface_up,
        default_route_present=default_route_present,
        internet_reachable=internet_reachable,
        dns_ok=internet_reachable,
        api_health_ok=api_health_ok,
        api_latency_ms=api_latency_ms,
        wifi_radio_enabled=wifi_radio_enabled,
        wifi_connected=wifi_connected,
        ethernet_connected=ethernet_connected,
        active_connections=[],
        rx_bytes=1000,
        tx_bytes=1000,
        notes=[],
    )


def test_fault_lab_agent_writes_telemetry_row(tmp_path: Path):
    snapshots = [
        _snapshot(internet_reachable=True, api_latency_ms=35.0),
        _snapshot(internet_reachable=False, api_health_ok=False, api_latency_ms=None),
    ]

    def collector(**kwargs):
        return snapshots.pop(0)

    config = FaultLabConfig(
        api_base_url="https://example.invalid/api",
        interface="sw-wg",
        output_dir=tmp_path / "fault",
        telemetry_path=tmp_path / "telemetry.csv",
        events_path=tmp_path / "events.jsonl",
        state_path=tmp_path / "state.json",
        qos_model_path=tmp_path / "qos.json",
        risk_model_path=tmp_path / "risk.json",
        run_network_drop=False,
        run_live_network_faults=False,
    )
    agent = FaultLabAgent(config, collector=collector)
    payload = agent.run_cycle()

    assert payload["telemetry"]["packet_loss"] == 1.0
    assert payload["telemetry"]["disconnect_count"] == 1

    rows = list(csv.DictReader(config.telemetry_path.open("r", encoding="utf-8")))
    assert len(rows) == 1
    assert rows[0]["qos_label"]


def test_recovery_agent_recommends_wifi_recovery(tmp_path: Path):
    telemetry_path = tmp_path / "telemetry.csv"
    telemetry_path.write_text(
        "\n".join(
            [
                "timestamp,user_id,server_id,latency_ms,packet_loss,jitter_ms,bandwidth_mbps,connection_stability,disconnect_count,session_duration_minutes,qos_label,risk_score",
                "2026-03-18T00:00:00Z,0,sw-wg,900.0,1.0,120.0,0.0,0.0,3,5.0,poor,0.8",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    events_path = tmp_path / "events.jsonl"
    events_path.write_text(
        '{"post":{"vpn_interface_up":true,"internet_reachable":false,"wifi_radio_enabled":false}}\n',
        encoding="utf-8",
    )

    def collector(**kwargs):
        return _snapshot(
            internet_reachable=False,
            wifi_radio_enabled=False,
            wifi_connected=False,
            default_route_present=False,
            api_health_ok=False,
            api_latency_ms=None,
        )

    config = RecoveryMlConfig(
        api_base_url="https://example.invalid/api",
        interface="sw-wg",
        telemetry_path=telemetry_path,
        events_path=events_path,
        output_dir=tmp_path / "recovery",
        qos_model_path=tmp_path / "qos.json",
        risk_model_path=tmp_path / "risk.json",
        execute_recovery=False,
        preferred_wifi_connection="LabWifi",
        min_training_records=99,
        patch_threshold=1,
    )
    agent = RecoveryMlAgent(config, collector=collector)
    payload = agent.run_cycle()

    action_names = [item["name"] for item in payload["actions"]]
    assert "enable_wifi_radio" in action_names
    assert "activate_wifi_connection" in action_names


def test_recovery_agent_emits_patch_recommendations_for_repeated_signature(tmp_path: Path):
    telemetry_path = tmp_path / "telemetry.csv"
    telemetry_path.write_text(
        "\n".join(
            [
                "timestamp,user_id,server_id,latency_ms,packet_loss,jitter_ms,bandwidth_mbps,connection_stability,disconnect_count,session_duration_minutes,qos_label,risk_score",
                "2026-03-18T00:00:00Z,0,sw-wg,900.0,1.0,120.0,0.0,0.0,3,5.0,poor,0.8",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    events_path = tmp_path / "events.jsonl"
    events_path.write_text(
        "\n".join(
            [
                '{"post":{"vpn_interface_up":true,"internet_reachable":false,"wifi_radio_enabled":false}}',
                '{"post":{"vpn_interface_up":true,"internet_reachable":false,"wifi_radio_enabled":false}}',
            ])
        + "\n",
        encoding="utf-8",
    )

    def collector(**kwargs):
        return _snapshot(
            internet_reachable=False,
            wifi_radio_enabled=False,
            default_route_present=False,
            api_health_ok=False,
            api_latency_ms=None,
        )

    config = RecoveryMlConfig(
        api_base_url="https://example.invalid/api",
        interface="sw-wg",
        telemetry_path=telemetry_path,
        events_path=events_path,
        output_dir=tmp_path / "recovery",
        qos_model_path=tmp_path / "qos.json",
        risk_model_path=tmp_path / "risk.json",
        patch_threshold=2,
        min_training_records=99,
    )
    agent = RecoveryMlAgent(config, collector=collector)
    payload = agent.run_cycle()

    recommendations = payload["patch_plan"]["recommendations"]
    assert any(item["signature"] == "internet_down_while_vpn_interface_up" for item in recommendations)


def test_runner_persists_consolidated_diagnostics_bundle(tmp_path: Path):
    output_dir = tmp_path / "runtime"
    diagnostics_dir = tmp_path / "vpn_diagnostics"
    models_dir = output_dir / "models"
    models_dir.mkdir(parents=True)
    (models_dir / "local_agent_qos.json").write_text('{"model":"qos"}\n', encoding="utf-8")
    (models_dir / "local_agent_risk.json").write_text('{"model":"risk"}\n', encoding="utf-8")

    payload = {
        "cycle": 1,
        "fault": {
            "scenarios": [{"harness": "network_drop", "overall_status": "ok"}],
            "telemetry": {"packet_loss": 1.0},
            "post": {"internet_reachable": False},
        },
        "recovery": {
            "actions": [
                {"name": "enable_wifi_radio", "ok": True, "executed": False},
                {"name": "bounce_vpn_interface_up", "ok": False, "executed": True},
            ],
            "snapshot_after": {"internet_reachable": False},
            "training": {"trained": False},
            "patch_plan": {"recommendations": []},
        },
    }

    run_securewave_vpn_agents._persist_diagnostics_bundle(
        payload,
        diagnostics_dir=diagnostics_dir,
        output_dir=output_dir,
    )

    assert (diagnostics_dir / "logs" / "logs.json").exists()
    assert (diagnostics_dir / "simulations" / "simulations.json").exists()
    assert (diagnostics_dir / "test_results" / "fixes.json").exists()
    assert (diagnostics_dir / "test_results" / "failures.json").exists()
    assert (diagnostics_dir / "model" / "model_stats.json").exists()
    assert (diagnostics_dir / "model" / "local_agent_qos.json").exists()
    assert (diagnostics_dir / "model" / "local_agent_risk.json").exists()
