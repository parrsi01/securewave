#!/usr/bin/env python3
"""DNS leak validation harness."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.leak_tests.common import interface_exists, read_text
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


def parse_nameservers(resolv_conf_text: str) -> list[str]:
    nameservers: list[str] = []
    for raw in resolv_conf_text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().startswith("nameserver"):
            parts = line.split()
            if len(parts) >= 2:
                nameservers.append(parts[1].strip())
    return nameservers


def evaluate_dns_servers(observed: list[str], allowed: set[str], allow_private: bool = True) -> tuple[bool, list[str]]:
    leaked: list[str] = []
    for ip_raw in observed:
        try:
            ip_obj = ipaddress.ip_address(ip_raw)
        except ValueError:
            leaked.append(ip_raw)
            continue
        if ip_raw in allowed:
            continue
        if allow_private and (ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local):
            continue
        leaked.append(ip_raw)
    return len(leaked) == 0, leaked


def run_harness(
    *,
    output_dir: Path,
    interface: str = "wg0",
    resolv_conf_path: str = "/etc/resolv.conf",
    expected_dns: list[str] | None = None,
    strict_live: bool = False,
) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    expected = expected_dns or [
        item.strip() for item in os.getenv("LEAK_EXPECTED_DNS", "94.140.14.14,94.140.15.15,1.1.1.1").split(",") if item.strip()
    ]
    allow_private = os.getenv("LEAK_ALLOW_PRIVATE_DNS", "true").lower() == "true"

    iface_present = interface_exists(interface)
    if not iface_present:
        status = "failed" if strict_live else "simulated"
        steps.append(
            StepResult(
                name="interface_check",
                status=status,
                duration_ms=0.0,
                detail=f"interface {interface} not present",
            )
        )
    else:
        steps.append(
            StepResult(name="interface_check", status="ok", duration_ms=0.0, detail=f"interface {interface} detected")
        )

    nameservers = parse_nameservers(read_text(resolv_conf_path))
    if not nameservers:
        steps.append(
            StepResult(name="resolver_parse", status="failed", duration_ms=0.0, detail="no nameservers discovered")
        )
    else:
        steps.append(
            StepResult(
                name="resolver_parse",
                status="ok",
                duration_ms=0.0,
                detail=f"resolved_nameservers={len(nameservers)}",
            )
        )

    if nameservers and (iface_present or strict_live):
        is_clean, leaked = evaluate_dns_servers(nameservers, set(expected), allow_private=allow_private)
        steps.append(
            StepResult(
                name="dns_leak_check",
                status="ok" if is_clean else "failed",
                duration_ms=0.0,
                detail="no_leak" if is_clean else f"leaked={','.join(leaked)}",
            )
        )
    elif nameservers:
        steps.append(
            StepResult(
                name="dns_leak_check",
                status="simulated",
                duration_ms=0.0,
                detail="no_live_interface; strict mode disabled",
            )
        )

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()

    result = HarnessResult(
        harness="dns_leak_test",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "interface": interface,
            "interface_present": iface_present,
            "strict_live": strict_live,
            "expected_dns": expected,
            "observed_dns": nameservers,
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "dns_leak_result.json", payload)

    lines = [
        "# DNS Leak Test Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- Interface present: `{iface_present}`",
        f"- Observed DNS: `{', '.join(nameservers) if nameservers else 'none'}`",
        "",
        "| Step | Status | Detail |",
        "|---|---|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.detail} |")
    write_markdown(out_dir / "dns_leak_summary.md", "\n".join(lines) + "\n")

    rows = "".join(f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.detail}</td></tr>" for s in steps)
    write_html(
        out_dir / "dns_leak_summary.html",
        title="DNS Leak Test Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate DNS leak protection")
    parser.add_argument("--output-dir", default="artifacts/leak_tests")
    parser.add_argument("--interface", default=os.getenv("WG_INTERFACE", "wg0"))
    parser.add_argument("--strict-live", action="store_true")
    parser.add_argument("--resolv-conf", default="/etc/resolv.conf")
    parser.add_argument("--expected-dns", default="")
    args = parser.parse_args()

    expected_dns = [v.strip() for v in args.expected_dns.split(",") if v.strip()] or None
    payload = run_harness(
        output_dir=Path(args.output_dir),
        interface=args.interface,
        resolv_conf_path=args.resolv_conf,
        expected_dns=expected_dns,
        strict_live=args.strict_live,
    )
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
