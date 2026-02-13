#!/usr/bin/env python3
"""IPv6 leak validation harness."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.leak_tests.common import default_routes, interface_exists, read_text, route_interfaces
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


def classify_ipv6_state(*, disabled_value: str, routes: list[str], interface: str, iface_present: bool, strict_live: bool) -> tuple[str, str]:
    disabled = disabled_value.strip() == "1"
    if disabled:
        return "ok", "ipv6_disabled"

    if not iface_present and not strict_live:
        return "simulated", "interface_missing_strict_disabled"

    interfaces = route_interfaces(routes)
    leaking_routes = [route for route, dev in zip(routes, interfaces) if dev != interface]
    if leaking_routes:
        return "failed", f"non_tunnel_ipv6_default={';'.join(leaking_routes)}"

    if iface_present and interface in interfaces:
        return "ok", "ipv6_default_via_tunnel"

    return "failed" if strict_live else "simulated", "no_ipv6_default_route"


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

    disabled_value = read_text("/proc/sys/net/ipv6/conf/all/disable_ipv6").strip() or "0"
    ipv6_routes = default_routes(ipv6=True)
    status, detail = classify_ipv6_state(
        disabled_value=disabled_value,
        routes=ipv6_routes,
        interface=interface,
        iface_present=iface_present,
        strict_live=strict_live,
    )
    steps.append(StepResult(name="ipv6_leak_check", status=status, duration_ms=0.0, detail=detail))

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()

    result = HarnessResult(
        harness="ipv6_leak_test",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "interface": interface,
            "interface_present": iface_present,
            "strict_live": strict_live,
            "ipv6_disabled_value": disabled_value,
            "ipv6_default_routes": ipv6_routes,
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "ipv6_leak_result.json", payload)

    lines = [
        "# IPv6 Leak Test Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- IPv6 disabled value: `{disabled_value}`",
        f"- IPv6 default routes: `{len(ipv6_routes)}`",
        "",
        "| Step | Status | Detail |",
        "|---|---|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.detail} |")
    write_markdown(out_dir / "ipv6_leak_summary.md", "\n".join(lines) + "\n")

    rows = "".join(f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.detail}</td></tr>" for s in steps)
    write_html(
        out_dir / "ipv6_leak_summary.html",
        title="IPv6 Leak Test Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate IPv6 leak protection")
    parser.add_argument("--output-dir", default="artifacts/leak_tests")
    parser.add_argument("--interface", default=os.getenv("WG_INTERFACE", "wg0"))
    parser.add_argument("--strict-live", action="store_true")
    args = parser.parse_args()

    payload = run_harness(output_dir=Path(args.output_dir), interface=args.interface, strict_live=args.strict_live)
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
