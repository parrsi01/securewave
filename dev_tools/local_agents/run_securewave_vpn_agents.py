#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from dev_tools.local_agents.common import ensure_dir, utc_now_iso
from dev_tools.local_agents.vpn_fault_lab_agent import FaultLabAgent, FaultLabConfig
from dev_tools.local_agents.vpn_recovery_ml_agent import RecoveryMlAgent, RecoveryMlConfig


def _load_json_list(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    return payload if isinstance(payload, list) else []


def _append_json_list(path: Path, record: dict) -> None:
    ensure_dir(path.parent)
    items = _load_json_list(path)
    items.append(record)
    path.write_text(json.dumps(items, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _ensure_json_list(path: Path) -> None:
    ensure_dir(path.parent)
    if path.exists():
        return
    path.write_text("[]\n", encoding="utf-8")


def _copy_if_present(source: Path, destination: Path) -> None:
    if not source.exists():
        return
    ensure_dir(destination.parent)
    shutil.copy2(source, destination)


def _persist_diagnostics_bundle(
    cycle_payload: dict,
    *,
    diagnostics_dir: Path,
    output_dir: Path,
) -> None:
    logs_dir = ensure_dir(diagnostics_dir / "logs")
    simulations_dir = ensure_dir(diagnostics_dir / "simulations")
    test_results_dir = ensure_dir(diagnostics_dir / "test_results")
    model_dir = ensure_dir(diagnostics_dir / "model")
    _ensure_json_list(logs_dir / "logs.json")
    _ensure_json_list(simulations_dir / "simulations.json")
    _ensure_json_list(test_results_dir / "fixes.json")
    _ensure_json_list(test_results_dir / "failures.json")

    cycle_record = {
        "captured_at": utc_now_iso(),
        "cycle": cycle_payload.get("cycle"),
        "payload": cycle_payload,
    }
    _append_json_list(logs_dir / "logs.json", cycle_record)

    fault_payload = cycle_payload.get("fault")
    if isinstance(fault_payload, dict):
        _append_json_list(
            simulations_dir / "simulations.json",
            {
                "captured_at": utc_now_iso(),
                "cycle": cycle_payload.get("cycle"),
                "scenarios": fault_payload.get("scenarios", []),
                "telemetry": fault_payload.get("telemetry", {}),
                "post_snapshot": fault_payload.get("post", {}),
            },
        )

    recovery_payload = cycle_payload.get("recovery")
    if isinstance(recovery_payload, dict):
        actions = list(recovery_payload.get("actions", []))
        fixes = [action for action in actions if action.get("ok", False)]
        failures = [action for action in actions if not action.get("ok", True)]
        if fixes:
            _append_json_list(
                test_results_dir / "fixes.json",
                {
                    "captured_at": utc_now_iso(),
                    "cycle": cycle_payload.get("cycle"),
                    "actions": fixes,
                    "patch_plan": recovery_payload.get("patch_plan", {}),
                },
            )
        if failures or recovery_payload.get("snapshot_after", {}).get("internet_reachable") is False:
            _append_json_list(
                test_results_dir / "failures.json",
                {
                    "captured_at": utc_now_iso(),
                    "cycle": cycle_payload.get("cycle"),
                    "actions": failures,
                    "snapshot_after": recovery_payload.get("snapshot_after", {}),
                    "patch_plan": recovery_payload.get("patch_plan", {}),
                },
            )

        model_stats = {
            "captured_at": utc_now_iso(),
            "cycle": cycle_payload.get("cycle"),
            "training": recovery_payload.get("training", {}),
            "patch_plan": recovery_payload.get("patch_plan", {}),
        }
        (model_dir / "model_stats.json").write_text(
            json.dumps(model_stats, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        _copy_if_present(output_dir / "models" / "local_agent_qos.json", model_dir / "local_agent_qos.json")
        _copy_if_present(output_dir / "models" / "local_agent_risk.json", model_dir / "local_agent_risk.json")


def _build_fault_config(args: argparse.Namespace) -> FaultLabConfig:
    return FaultLabConfig(
        api_base_url=args.api_base_url,
        interface=args.interface,
        output_dir=Path(args.output_dir) / "fault_lab",
        telemetry_path=Path(args.output_dir) / "vpn_fault_lab_telemetry.csv",
        events_path=Path(args.output_dir) / "fault_lab" / "fault_lab_events.jsonl",
        state_path=Path(args.output_dir) / "fault_lab" / "fault_lab_state.json",
        qos_model_path=Path(args.output_dir) / "models" / "local_agent_qos.json",
        risk_model_path=Path(args.output_dir) / "models" / "local_agent_risk.json",
        run_network_drop=not args.disable_network_drop,
        run_live_network_faults=not args.disable_live_faults,
        execute_destructive=args.execute_destructive,
    )


def _build_recovery_config(args: argparse.Namespace) -> RecoveryMlConfig:
    return RecoveryMlConfig(
        api_base_url=args.api_base_url,
        interface=args.interface,
        telemetry_path=Path(args.output_dir) / "vpn_fault_lab_telemetry.csv",
        events_path=Path(args.output_dir) / "fault_lab" / "fault_lab_events.jsonl",
        output_dir=Path(args.output_dir) / "recovery_ml",
        qos_model_path=Path(args.output_dir) / "models" / "local_agent_qos.json",
        risk_model_path=Path(args.output_dir) / "models" / "local_agent_risk.json",
        execute_recovery=args.execute_recovery,
        allow_vpn_bounce=args.allow_vpn_bounce,
        preferred_wifi_connection=args.preferred_wifi_connection,
        min_training_records=args.min_training_records,
        patch_threshold=args.patch_threshold,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Run local SecureWave VPN fault/recovery agents")
    parser.add_argument("--agent", choices=("fault", "recovery", "all"), default="all")
    parser.add_argument("--cycles", type=int, default=1, help="How many cycles to run (0 means forever)")
    parser.add_argument("--interval-seconds", type=float, default=30.0)
    parser.add_argument("--api-base-url", default="https://138.199.204.139.nip.io/api")
    parser.add_argument("--interface", default="sw-wg")
    parser.add_argument("--output-dir", default="artifacts/local_agents/runtime")
    parser.add_argument("--diagnostics-dir", default="vpn_diagnostics")
    parser.add_argument("--disable-network-drop", action="store_true")
    parser.add_argument("--disable-live-faults", action="store_true")
    parser.add_argument("--execute-destructive", action="store_true")
    parser.add_argument("--execute-recovery", action="store_true")
    parser.add_argument("--allow-vpn-bounce", action="store_true")
    parser.add_argument("--preferred-wifi-connection", default=None)
    parser.add_argument("--min-training-records", type=int, default=10)
    parser.add_argument("--patch-threshold", type=int, default=3)
    args = parser.parse_args()

    fault_agent = FaultLabAgent(_build_fault_config(args))
    recovery_agent = RecoveryMlAgent(_build_recovery_config(args))

    cycle = 0
    results = []
    while args.cycles == 0 or cycle < args.cycles:
        cycle += 1
        cycle_payload = {"cycle": cycle}
        if args.agent in {"fault", "all"}:
            cycle_payload["fault"] = fault_agent.run_cycle()
        if args.agent in {"recovery", "all"}:
            cycle_payload["recovery"] = recovery_agent.run_cycle()
        results.append(cycle_payload)
        _persist_diagnostics_bundle(
            cycle_payload,
            diagnostics_dir=Path(args.diagnostics_dir),
            output_dir=Path(args.output_dir),
        )
        print(json.dumps(cycle_payload, indent=2, sort_keys=True))
        if args.cycles != 0 and cycle >= args.cycles:
            break
        time.sleep(max(1.0, args.interval_seconds))

    summary = {
        "agent_mode": args.agent,
        "cycles": cycle,
        "diagnostics_dir": args.diagnostics_dir,
        "output_dir": args.output_dir,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
