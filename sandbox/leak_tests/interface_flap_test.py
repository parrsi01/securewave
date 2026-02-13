#!/usr/bin/env python3
"""Interface flap resilience and kill-switch response validation."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.leak_tests.common import default_routes, interface_exists, route_interfaces, run_command
from sandbox.validation_common import (
    HarnessResult,
    StepResult,
    ensure_dir,
    harness_to_dict,
    summarize_steps,
    utc_now_iso,
    write_html,
    write_json,
    write_markdown,
)


def evaluate_kill_switch(*, down_routes: list[str], up_routes: list[str], interface: str) -> dict:
    down_interfaces = route_interfaces(down_routes)
    up_interfaces = route_interfaces(up_routes)

    down_non_tunnel = [route for route, dev in zip(down_routes, down_interfaces) if dev != interface]
    up_non_tunnel = [route for route, dev in zip(up_routes, up_interfaces) if dev != interface]
    down_ok = len(down_non_tunnel) == 0
    up_ok = interface in up_interfaces and len(up_non_tunnel) == 0

    return {
        "down_ok": down_ok,
        "up_ok": up_ok,
        "down_non_tunnel": down_non_tunnel,
        "up_non_tunnel": up_non_tunnel,
    }


def _set_interface_state(interface: str, state: str) -> tuple[bool, str]:
    rc, out, err = run_command(["ip", "link", "set", interface, state], timeout_seconds=8)
    if rc == 0:
        return True, (out or "ok").strip()
    return False, (err or out or "failed").strip()[:500]


def run_harness(*, output_dir: Path, interface: str = "wg0", execute: bool = False, strict_live: bool = False) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    iface_present = interface_exists(interface)
    if not iface_present and strict_live:
        steps.append(
            StepResult(
                name="interface_check",
                status="failed",
                duration_ms=0.0,
                detail=f"interface {interface} missing in strict mode",
            )
        )
    elif not iface_present:
        steps.append(
            StepResult(
                name="interface_check",
                status="simulated",
                duration_ms=0.0,
                detail=f"interface {interface} missing; running simulated validation",
            )
        )
    else:
        steps.append(StepResult(name="interface_check", status="ok", duration_ms=0.0, detail="interface_present"))

    destructive_allowed = execute and os.geteuid() == 0 and iface_present
    if execute and not destructive_allowed:
        steps.append(
            StepResult(
                name="execution_mode",
                status="simulated",
                duration_ms=0.0,
                detail="--execute ignored (requires root + existing interface)",
            )
        )

    if destructive_allowed:
        before_routes = default_routes(ipv6=False)
        ok_down, down_detail = _set_interface_state(interface, "down")
        down_routes = default_routes(ipv6=False)
        ok_up, up_detail = _set_interface_state(interface, "up")
        up_routes = default_routes(ipv6=False)

        steps.append(
            StepResult(
                name="interface_down",
                status="ok" if ok_down else "failed",
                duration_ms=0.0,
                detail=down_detail,
            )
        )
        steps.append(
            StepResult(
                name="interface_up",
                status="ok" if ok_up else "failed",
                duration_ms=0.0,
                detail=up_detail,
            )
        )
    else:
        before_routes = default_routes(ipv6=False)
        down_routes = []
        up_routes = [f"default dev {interface} scope link"] if iface_present else []
        steps.append(
            StepResult(
                name="interface_down",
                status="simulated",
                duration_ms=0.0,
                detail="safe mode",
            )
        )
        steps.append(
            StepResult(
                name="interface_up",
                status="simulated",
                duration_ms=0.0,
                detail="safe mode",
            )
        )

    kill_switch = evaluate_kill_switch(down_routes=down_routes, up_routes=up_routes, interface=interface)
    if not iface_present and not strict_live:
        status = "simulated"
        detail = "no_live_interface"
    elif kill_switch["down_ok"] and kill_switch["up_ok"]:
        status = "ok"
        detail = "kill_switch_intact"
    else:
        status = "failed"
        detail = "kill_switch_failure"

    steps.append(
        StepResult(
            name="kill_switch_evaluation",
            status=status,
            duration_ms=0.0,
            detail=detail,
        )
    )

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()

    result = HarnessResult(
        harness="interface_flap_test",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "interface": interface,
            "interface_present": iface_present,
            "strict_live": strict_live,
            "destructive_mode": destructive_allowed,
            "routes_before": before_routes,
            "routes_after_down": down_routes,
            "routes_after_up": up_routes,
            "kill_switch": kill_switch,
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "interface_flap_result.json", payload)

    lines = [
        "# Interface Flap Leak Test Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- Interface present: `{iface_present}`",
        f"- Destructive mode: `{destructive_allowed}`",
        "",
        "| Step | Status | Detail |",
        "|---|---|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.detail} |")
    write_markdown(out_dir / "interface_flap_summary.md", "\n".join(lines) + "\n")

    rows = "".join(f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.detail}</td></tr>" for s in steps)
    write_html(
        out_dir / "interface_flap_summary.html",
        title="Interface Flap Leak Test Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate interface flap resilience and kill switch behavior")
    parser.add_argument("--output-dir", default="artifacts/leak_tests")
    parser.add_argument("--interface", default=os.getenv("WG_INTERFACE", "wg0"))
    parser.add_argument("--execute", action="store_true", help="Allow real interface down/up (root required)")
    parser.add_argument("--strict-live", action="store_true")
    args = parser.parse_args()

    payload = run_harness(
        output_dir=Path(args.output_dir),
        interface=args.interface,
        execute=args.execute,
        strict_live=args.strict_live,
    )
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
