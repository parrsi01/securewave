#!/usr/bin/env python3
"""Route-table leak validation harness."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.leak_tests.common import default_routes, interface_exists, route_interfaces
from dev_tools.sandbox.validation_common import (
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


def route_leak_detected(routes: list[str], interface: str) -> tuple[bool, list[str], bool]:
    interfaces = route_interfaces(routes)
    non_tunnel = [route for route, dev in zip(routes, interfaces) if dev != interface]
    has_tunnel_default = interface in interfaces
    return len(non_tunnel) > 0, non_tunnel, has_tunnel_default


def run_harness(*, output_dir: Path, interface: str = "wg0", strict_live: bool = False) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    iface_present = interface_exists(interface)
    steps.append(
        StepResult(
            name="interface_check",
            status="ok" if iface_present else ("failed" if strict_live else "simulated"),
            duration_ms=0.0,
            detail=f"interface_present={iface_present}",
        )
    )

    routes = default_routes(ipv6=False)
    leak, non_tunnel, has_tunnel = route_leak_detected(routes, interface)

    if not iface_present and not strict_live:
        status = "simulated"
        detail = "interface_missing_strict_disabled"
    elif leak:
        status = "failed"
        detail = f"non_tunnel_defaults={';'.join(non_tunnel)}"
    elif not has_tunnel:
        status = "failed" if strict_live else "simulated"
        detail = "no_tunnel_default_route"
    else:
        status = "ok"
        detail = "all_default_routes_via_tunnel"

    steps.append(StepResult(name="route_integrity_check", status=status, duration_ms=0.0, detail=detail))

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()

    result = HarnessResult(
        harness="route_table_test",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "interface": interface,
            "interface_present": iface_present,
            "strict_live": strict_live,
            "default_routes": routes,
            "non_tunnel_defaults": non_tunnel,
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "route_table_result.json", payload)

    lines = [
        "# Route Table Leak Test Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- Default routes observed: `{len(routes)}`",
        "",
        "| Step | Status | Detail |",
        "|---|---|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.detail} |")
    write_markdown(out_dir / "route_table_summary.md", "\n".join(lines) + "\n")

    rows = "".join(f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.detail}</td></tr>" for s in steps)
    write_html(
        out_dir / "route_table_summary.html",
        title="Route Table Leak Test Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate route table tunnel integrity")
    parser.add_argument("--output-dir", default="artifacts/leak_tests")
    parser.add_argument("--interface", default=os.getenv("WG_INTERFACE", "wg0"))
    parser.add_argument("--strict-live", action="store_true")
    args = parser.parse_args()

    payload = run_harness(output_dir=Path(args.output_dir), interface=args.interface, strict_live=args.strict_live)
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
