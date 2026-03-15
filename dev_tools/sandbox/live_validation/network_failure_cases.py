#!/usr/bin/env python3
"""Network fault injection for live SecureWave validation."""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import tempfile
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import build_api_url, ensure_dir, run_command, utc_now_iso, write_json, write_markdown


def categorize_fault_result(status: str, recovered: bool) -> str:
    if status == "simulated":
        return "simulated"
    if status == "pass" and recovered:
        return "recovered"
    if status == "pass" and not recovered:
        return "partial"
    return "failed"


def _scenario_backend_unreachable(api_base_url: str, execute: bool) -> dict[str, Any]:
    if not execute:
        return {
            "scenario": "backend_unreachable_during_handshake",
            "status": "simulated",
            "detail": "would block backend host via iptables",
            "recovered": True,
        }

    host = api_base_url.split("//")[-1].split("/")[0].split(":")[0]
    try:
        host_ip = socket.gethostbyname(host)
    except Exception:
        return {
            "scenario": "backend_unreachable_during_handshake",
            "status": "failed",
            "detail": "cannot_resolve_backend_host",
            "recovered": False,
        }

    add_rule = run_command(["iptables", "-I", "OUTPUT", "1", "-d", host_ip, "-j", "REJECT"], timeout_seconds=12)
    failed_as_expected = False
    if add_rule.returncode == 0:
        probe = run_command(["curl", "--max-time", "6", "-sS", build_api_url(api_base_url, "/health")], timeout_seconds=8)
        failed_as_expected = probe.returncode != 0
    remove_rule = run_command(["iptables", "-D", "OUTPUT", "-d", host_ip, "-j", "REJECT"], timeout_seconds=12)

    status = "pass" if add_rule.returncode == 0 and remove_rule.returncode == 0 and failed_as_expected else "failed"
    return {
        "scenario": "backend_unreachable_during_handshake",
        "status": status,
        "detail": f"add={add_rule.returncode},remove={remove_rule.returncode},probe_failed={failed_as_expected}",
        "recovered": remove_rule.returncode == 0,
    }


def _scenario_wireguard_process_crash(interface: str, execute: bool) -> dict[str, Any]:
    if not execute:
        return {
            "scenario": "wireguard_process_crash",
            "status": "simulated",
            "detail": f"would toggle interface {interface} down/up",
            "recovered": True,
        }

    down = run_command(["ip", "link", "set", interface, "down"], timeout_seconds=12)
    up = run_command(["ip", "link", "set", interface, "up"], timeout_seconds=12)
    status = "pass" if down.returncode == 0 and up.returncode == 0 else "failed"
    return {
        "scenario": "wireguard_process_crash",
        "status": status,
        "detail": f"down={down.returncode},up={up.returncode}",
        "recovered": up.returncode == 0,
    }


def _scenario_gateway_reset(execute: bool, api_base_url: str) -> dict[str, Any]:
    if not execute:
        return {
            "scenario": "gateway_reset",
            "status": "simulated",
            "detail": "would remove default route then restore",
            "recovered": True,
        }

    snapshot = run_command(["ip", "route", "show", "default"], timeout_seconds=8)
    line = snapshot.stdout.splitlines()[0].strip() if snapshot.stdout else ""
    if snapshot.returncode != 0 or not line:
        return {
            "scenario": "gateway_reset",
            "status": "failed",
            "detail": "unable_to_snapshot_default_route",
            "recovered": False,
        }

    # Temporarily remove defaults to simulate gateway reset.
    delete_cmd = run_command(["ip", "route", "del", "default"], timeout_seconds=8)
    probe = run_command(["curl", "--max-time", "5", "-sS", build_api_url(api_base_url, "/health")], timeout_seconds=7)
    restore = run_command(f"ip route replace {line}", timeout_seconds=8, shell=True)

    degraded = probe.returncode != 0
    status = "pass" if delete_cmd.returncode == 0 and restore.returncode == 0 and degraded else "failed"
    return {
        "scenario": "gateway_reset",
        "status": status,
        "detail": f"delete={delete_cmd.returncode},restore={restore.returncode},degraded={degraded}",
        "recovered": restore.returncode == 0,
    }


def _scenario_dns_unresponsive(execute: bool) -> dict[str, Any]:
    if not execute:
        return {
            "scenario": "dns_server_unresponsive",
            "status": "simulated",
            "detail": "would swap resolv.conf nameserver and restore",
            "recovered": True,
        }

    resolv_path = Path("/etc/resolv.conf")
    if not resolv_path.exists() or not os.access(resolv_path, os.W_OK):
        return {
            "scenario": "dns_server_unresponsive",
            "status": "failed",
            "detail": "resolv_conf_not_writable",
            "recovered": False,
        }

    backup = resolv_path.read_text(encoding="utf-8", errors="ignore")
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as handle:
        handle.write("nameserver 203.0.113.250\n")
        tmp_path = Path(handle.name)

    try:
        replace = run_command(["cp", str(tmp_path), str(resolv_path)], timeout_seconds=6)
        probe = run_command(["getent", "hosts", "example.com"], timeout_seconds=6)
        restore = run_command(["sh", "-lc", f"cat <<'EOF' > {resolv_path}\n{backup}\nEOF"], timeout_seconds=6)
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass

    degraded = probe.returncode != 0
    status = "pass" if replace.returncode == 0 and restore.returncode == 0 and degraded else "failed"
    return {
        "scenario": "dns_server_unresponsive",
        "status": status,
        "detail": f"replace={replace.returncode},restore={restore.returncode},degraded={degraded}",
        "recovered": restore.returncode == 0,
    }


def run_fault_cases(*, output_dir: Path, api_base_url: str, interface: str, execute: bool, strict: bool) -> dict[str, Any]:
    out_dir = ensure_dir(output_dir)

    is_root = bool(hasattr(os, "geteuid") and os.geteuid() == 0)
    destructive_allowed = execute and is_root
    scenarios = [
        _scenario_backend_unreachable(api_base_url, destructive_allowed),
        _scenario_wireguard_process_crash(interface, destructive_allowed),
        _scenario_gateway_reset(destructive_allowed, api_base_url),
        _scenario_dns_unresponsive(destructive_allowed),
    ]

    strict_failures = 0
    for scenario in scenarios:
        if strict and scenario.get("status") != "pass":
            strict_failures += 1

    payload = {
        "harness": "network_failure_cases",
        "generated_at": utc_now_iso(),
        "overall_status": "pass" if strict_failures == 0 else "fail",
        "strict": strict,
        "execute": execute,
        "destructive_allowed": destructive_allowed,
        "scenarios": [
            {
                **scenario,
                "category": categorize_fault_result(str(scenario.get("status")), bool(scenario.get("recovered"))),
            }
            for scenario in scenarios
        ],
    }

    write_json(out_dir / "network_faults_result.json", payload)

    lines = [
        "# Network Fault Injection Summary",
        "",
        f"- Generated: `{payload['generated_at']}`",
        f"- Overall: **{payload['overall_status']}**",
        f"- Strict mode: `{strict}`",
        f"- Execute mode: `{execute}`",
        f"- Destructive allowed: `{destructive_allowed}`",
        "",
        "| Scenario | Status | Category | Detail |",
        "|---|---|---|---|",
    ]
    for item in payload["scenarios"]:
        lines.append(
            f"| {item['scenario']} | {item['status']} | {item['category']} | {item['detail']} |"
        )
    write_markdown(out_dir / "network_faults_summary.md", "\n".join(lines) + "\n")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Inject live network failures and validate recovery")
    parser.add_argument("--output-dir", default="artifacts/live_validation")
    parser.add_argument("--api-base-url", default=os.getenv("LIVE_API_BASE_URL", ""))
    parser.add_argument("--interface", default=os.getenv("LIVE_VALIDATION_INTERFACE", "wg0"))
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if not args.api_base_url.strip():
        raise SystemExit("LIVE_API_BASE_URL is required")

    payload = run_fault_cases(
        output_dir=Path(args.output_dir),
        api_base_url=args.api_base_url.strip(),
        interface=args.interface,
        execute=args.execute,
        strict=args.strict,
    )
    print(json.dumps(payload, indent=2))
    return 0 if payload.get("overall_status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
