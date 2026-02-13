#!/usr/bin/env python3
"""WireGuard/network failure injection harness."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess  # nosec B404 - controlled operator tooling
import time
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.validation_common import (
    HarnessResult,
    StepResult,
    bool_env,
    ensure_dir,
    harness_to_dict,
    summarize_steps,
    utc_now_iso,
    write_html,
    write_json,
    write_markdown,
)


def _command_step(name: str, command: list[str], *, allow_failure: bool = False) -> StepResult:
    started = time.monotonic()
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=False, timeout=12)  # nosec B603
        combined = (proc.stdout + "\n" + proc.stderr).strip()
        if proc.returncode == 0:
            status = "ok"
            detail = "executed"
        elif allow_failure:
            status = "simulated"
            detail = f"non_fatal_exit={proc.returncode}"
        else:
            status = "failed"
            detail = f"exit_code={proc.returncode}"
        return StepResult(
            name=name,
            status=status,
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=detail,
            command=" ".join(command),
            output=combined[:4000],
        )
    except Exception as exc:  # pragma: no cover - environment dependent
        return StepResult(
            name=name,
            status="failed" if not allow_failure else "simulated",
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=f"exception={exc}",
            command=" ".join(command),
            output=str(exc),
        )


def _snapshot_step(name: str, command: list[str]) -> tuple[StepResult, str | None]:
    started = time.monotonic()
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=False, timeout=12)  # nosec B603
        combined = (proc.stdout + "\n" + proc.stderr).strip()
        if proc.returncode == 0:
            return (
                StepResult(
                    name=name,
                    status="ok",
                    duration_ms=round((time.monotonic() - started) * 1000, 2),
                    detail="snapshot_ok",
                    command=" ".join(command),
                    output=combined[:4000],
                ),
                proc.stdout,
            )
        return (
            StepResult(
                name=name,
                status="failed",
                duration_ms=round((time.monotonic() - started) * 1000, 2),
                detail=f"snapshot_failed_exit={proc.returncode}",
                command=" ".join(command),
                output=combined[:4000],
            ),
            None,
        )
    except Exception as exc:  # pragma: no cover - environment dependent
        return (
            StepResult(
                name=name,
                status="failed",
                duration_ms=round((time.monotonic() - started) * 1000, 2),
                detail=f"snapshot_exception={exc}",
                command=" ".join(command),
                output=str(exc),
            ),
            None,
        )


def _restore_step(name: str, command: list[str], snapshot_text: str) -> StepResult:
    started = time.monotonic()
    try:
        proc = subprocess.run(  # nosec B603
            command,
            input=snapshot_text,
            capture_output=True,
            text=True,
            check=False,
            timeout=12,
        )
        combined = (proc.stdout + "\n" + proc.stderr).strip()
        if proc.returncode == 0:
            status = "ok"
            detail = "restore_ok"
        else:
            status = "failed"
            detail = f"restore_failed_exit={proc.returncode}"
        return StepResult(
            name=name,
            status=status,
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=detail,
            command=" ".join(command),
            output=combined[:4000],
        )
    except Exception as exc:  # pragma: no cover - environment dependent
        return StepResult(
            name=name,
            status="failed",
            duration_ms=round((time.monotonic() - started) * 1000, 2),
            detail=f"restore_exception={exc}",
            command=" ".join(command),
            output=str(exc),
        )


def _interface_exists(interface: str) -> bool:
    ip_path = shutil.which("ip")
    if not ip_path:
        return False
    result = subprocess.run([ip_path, "link", "show", interface], capture_output=True, text=True, check=False)  # nosec B603
    return result.returncode == 0


def _interface_is_up(interface: str) -> bool:
    ip_path = shutil.which("ip")
    if not ip_path:
        return False
    result = subprocess.run([ip_path, "link", "show", interface], capture_output=True, text=True, check=False)  # nosec B603
    if result.returncode != 0:
        return False

    text = result.stdout or ""
    if "state UP" in text:
        return True
    if "<" in text and ">" in text:
        try:
            flags_blob = text.split("<", 1)[1].split(">", 1)[0]
            flags = [item.strip() for item in flags_blob.split(",") if item.strip()]
            if "UP" in flags:
                return True
        except Exception:
            return False
    return "UP" in text


def _wg_show_ok(interface: str) -> bool:
    wg_path = shutil.which("wg")
    if not wg_path:
        return True
    result = subprocess.run([wg_path, "show", interface], capture_output=True, text=True, check=False)  # nosec B603
    return result.returncode == 0


def _wait_for_recovery(interface: str, timeout_s: float = 20.0) -> tuple[bool, str]:
    start = time.monotonic()
    while (time.monotonic() - start) <= timeout_s:
        if _interface_is_up(interface) and _wg_show_ok(interface):
            return True, "recovered"
        time.sleep(0.25)
    return False, f"recovery_timeout_s={timeout_s}"


def run_harness(*, output_dir: Path, interface: str = "wg0", execute: bool = False) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    destructive_allowed = execute and os.geteuid() == 0
    iface_present = _interface_exists(interface)
    recovery_start: float | None = None

    if not destructive_allowed:
        steps.append(
            StepResult(
                name="preflight",
                status="simulated",
                duration_ms=0.0,
                detail="running in safe mode (use --execute as root to inject real faults)",
            )
        )
    else:
        steps.append(StepResult(name="preflight", status="ok", duration_ms=0.0, detail="destructive mode enabled"))

    iptables_snapshot: str | None = None
    ip6tables_snapshot: str | None = None
    if destructive_allowed:
        iptables_save = shutil.which("iptables-save")
        iptables_restore = shutil.which("iptables-restore")
        if iptables_save and iptables_restore:
            snapshot_step, iptables_snapshot = _snapshot_step("iptables_snapshot", [iptables_save])
            steps.append(snapshot_step)
        else:
            steps.append(
                StepResult(
                    name="iptables_snapshot",
                    status="simulated",
                    duration_ms=0.0,
                    detail="iptables-save/iptables-restore missing; skipping iptables destructive steps",
                )
            )

        ip6tables_save = shutil.which("ip6tables-save")
        ip6tables_restore = shutil.which("ip6tables-restore")
        if ip6tables_save and ip6tables_restore:
            snapshot_step, ip6tables_snapshot = _snapshot_step("ip6tables_snapshot", [ip6tables_save])
            steps.append(snapshot_step)
        else:
            steps.append(
                StepResult(
                    name="ip6tables_snapshot",
                    status="simulated",
                    duration_ms=0.0,
                    detail="ip6tables-save/ip6tables-restore missing; skipping ip6tables destructive steps",
                )
            )

    actions = [
        ("wireguard_process_crash", ["pkill", "-f", "wg-quick|wireguard|wg0"], True),
        ("iptables_flush", ["iptables", "-F"], False),
        ("ip6tables_flush", ["ip6tables", "-F"], False),
        ("interface_down", ["ip", "link", "set", interface, "down"], True),
        ("firewall_rule_removal", ["iptables", "-D", "INPUT", "-p", "udp", "--dport", "51820", "-j", "ACCEPT"], True),
        ("interface_up", ["ip", "link", "set", interface, "up"], True),
    ]

    for name, cmd, non_fatal in actions:
        if not destructive_allowed:
            steps.append(
                StepResult(
                    name=name,
                    status="simulated",
                    duration_ms=0.0,
                    detail="safe mode",
                    command=" ".join(cmd),
                )
            )
            continue

        if name == "iptables_flush" or name == "firewall_rule_removal":
            if iptables_snapshot is None:
                steps.append(
                    StepResult(
                        name=name,
                        status="simulated",
                        duration_ms=0.0,
                        detail="skipped_no_snapshot",
                        command=" ".join(cmd),
                    )
                )
                continue

        if name == "ip6tables_flush":
            if ip6tables_snapshot is None:
                steps.append(
                    StepResult(
                        name=name,
                        status="simulated",
                        duration_ms=0.0,
                        detail="skipped_no_snapshot",
                        command=" ".join(cmd),
                    )
                )
                continue

        if "interface" in name and not iface_present:
            steps.append(
                StepResult(
                    name=name,
                    status="simulated",
                    duration_ms=0.0,
                    detail=f"{interface} not present",
                    command=" ".join(cmd),
                )
            )
            continue

        if name == "interface_down":
            recovery_start = time.monotonic()
        steps.append(_command_step(name, cmd, allow_failure=non_fatal))

    if destructive_allowed and iptables_snapshot is not None:
        restore_cmd = [shutil.which("iptables-restore") or "iptables-restore"]
        steps.append(_restore_step("iptables_restore", restore_cmd, iptables_snapshot))
    if destructive_allowed and ip6tables_snapshot is not None:
        restore_cmd = [shutil.which("ip6tables-restore") or "ip6tables-restore"]
        steps.append(_restore_step("ip6tables_restore", restore_cmd, ip6tables_snapshot))

    recovery_time_ms: float | None = None
    recovery_probe_ok: bool | None = None
    if destructive_allowed and iface_present and recovery_start is not None:
        probe_start = time.monotonic()
        ok, detail = _wait_for_recovery(interface, timeout_s=20.0)
        steps.append(
            StepResult(
                name="recovery_probe",
                status="ok" if ok else "failed",
                duration_ms=round((time.monotonic() - probe_start) * 1000, 2),
                detail=detail,
            )
        )
        recovery_time_ms = round((time.monotonic() - recovery_start) * 1000, 2)
        recovery_probe_ok = ok

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"

    finished = utc_now_iso()
    result = HarnessResult(
        harness="network_drop",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "interface": interface,
            "interface_present": iface_present,
            "destructive_mode": destructive_allowed,
            **({"recovery_time_ms": recovery_time_ms} if recovery_time_ms is not None else {}),
            **({"recovery_probe_ok": recovery_probe_ok} if recovery_probe_ok is not None else {}),
            **totals,
        },
    )

    payload = harness_to_dict(result)
    out_dir = ensure_dir(output_dir)
    json_path = out_dir / "network_drop_result.json"
    md_path = out_dir / "network_drop_summary.md"
    html_path = out_dir / "network_drop_summary.html"
    write_json(json_path, payload)

    lines = [
        "# Network Drop Chaos Summary",
        "",
        f"- Overall status: **{overall}**",
        f"- Started: `{started}`",
        f"- Finished: `{finished}`",
        f"- Interface: `{interface}` (present={iface_present})",
        f"- Destructive mode: `{destructive_allowed}`",
        "",
        "## Step Results",
        "",
        "| Step | Status | Duration (ms) | Detail |",
        "|---|---|---:|---|",
    ]
    for step in steps:
        lines.append(f"| {step.name} | {step.status} | {step.duration_ms:.2f} | {step.detail} |")
    write_markdown(md_path, "\n".join(lines) + "\n")

    body_rows = "".join(
        f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.duration_ms:.2f}</td><td>{s.detail}</td></tr>" for s in steps
    )
    write_html(
        html_path,
        title="Network Drop Chaos Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            f"<p><strong>Interface:</strong> {interface} (present={iface_present})</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Duration (ms)</th><th>Detail</th></tr></thead>"
            f"<tbody>{body_rows}</tbody></table>"
        ),
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Inject WireGuard/network failure scenarios")
    parser.add_argument("--output-dir", default="artifacts/chaos_tests")
    parser.add_argument("--interface", default=os.getenv("WG_INTERFACE", "wg0"))
    parser.add_argument("--execute", action="store_true", help="Allow destructive actions (requires root)")
    args = parser.parse_args()

    payload = run_harness(output_dir=Path(args.output_dir), interface=args.interface, execute=args.execute)
    print(payload["overall_status"])
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
