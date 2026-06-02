#!/usr/bin/env python3
"""Verify local Linux VPN runtime prerequisites and residue state.

This is intentionally read-only. It does not start tunnels. Use it before and
after app-driven VPN attempts to prove the host has the expected runtime tools
and no stale SecureWave tunnel/process residue.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = REPO_ROOT / "securewave_app/linux/runner/my_application.cc"
BUILD_PATH = REPO_ROOT / "securewave_app/build/linux/arm64/debug/bundle/securewave_app"
REQUIRED_TOOLS = ("wg-quick", "wg", "openvpn", "nmcli", "swanctl", "ipsec", "ip", "pkexec")
WIREGUARD_INTERFACE = "sw-wg"
IKEV2_CONNECTION = "SecureWave-IKEv2"


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str

    def as_dict(self) -> dict[str, object]:
        return {"name": self.name, "ok": self.ok, "detail": self.detail}


def _run(argv: Iterable[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def check_tools() -> list[Check]:
    checks: list[Check] = []
    for tool in REQUIRED_TOOLS:
        path = shutil.which(tool)
        checks.append(
            Check(
                name=f"tool:{tool}",
                ok=path is not None,
                detail=path or f"{tool} not found in PATH",
            )
        )
    return checks


def check_privilege_elevation() -> Check:
    if shutil.which("pkexec") is None:
        return Check(
            "privilege:pkexec_authorization",
            False,
            "pkexec not found in PATH",
        )
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return Check(
            "privilege:pkexec_authorization",
            True,
            "running as root; pkexec not required",
        )
    try:
        completed = subprocess.run(
            ["pkexec", "/usr/bin/true"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        return Check(
            "privilege:pkexec_authorization",
            False,
            "pkexec authorization timed out; start a PolicyKit authentication agent or run SecureWave with required privileges",
        )
    return Check(
        "privilege:pkexec_authorization",
        completed.returncode == 0,
        "pkexec authorization works"
        if completed.returncode == 0
        else completed.stderr.strip() or f"pkexec exited {completed.returncode}",
    )


def check_runner_contract() -> list[Check]:
    if not RUNNER_PATH.exists():
        return [Check("runner:source", False, f"{RUNNER_PATH} not found")]
    source = RUNNER_PATH.read_text(encoding="utf-8")
    expectations = {
        "runner:wireguard": "persist_active_protocol(state, \"wireguard\")",
        "runner:wireguard_route_evidence": "route traffic was not using interface %s",
        "runner:wireguard_helper": "/usr/local/libexec/securewave-wg-quick",
        "runner:openvpn": "persist_active_protocol(state, \"openvpn\")",
        "runner:openvpn_helper_start": "openvpn-start",
        "runner:openvpn_helper_stop": "openvpn-stop",
        "runner:ikev2": "persist_active_protocol(state, \"ikev2\")",
        "runner:ikev2_helper_add": "ikev2-add-eap",
        "runner:ikev2_helper_up": "ikev2-up",
        "runner:openvpn_tunnel_evidence": "OpenVPN process started but no tunnel interface or tunnel route was detected.",
        "runner:ikev2_runtime_evidence": "active NetworkManager VPN route or DNS evidence was not detected",
        "runner:no_implicit_mock": "securewave/vpn",
    }
    return [
        Check(name, token in source, "present" if token in source else f"missing {token!r}")
        for name, token in expectations.items()
    ]


def check_build_artifact() -> Check:
    return Check(
        "build:linux_debug_bundle",
        BUILD_PATH.exists(),
        str(BUILD_PATH) if BUILD_PATH.exists() else "run: cd securewave_app && flutter build linux --debug",
    )


def check_residue() -> list[Check]:
    checks: list[Check] = []

    link = _run(["ip", "link", "show", WIREGUARD_INTERFACE])
    checks.append(
        Check(
            "residue:wireguard_interface",
            link.returncode != 0,
            f"{WIREGUARD_INTERFACE} interface absent"
            if link.returncode != 0
            else f"{WIREGUARD_INTERFACE} interface is still present",
        )
    )

    tun0 = _run(["ip", "link", "show", "tun0"])
    checks.append(
        Check(
            "residue:tun0_interface",
            tun0.returncode != 0,
            "tun0 interface absent" if tun0.returncode != 0 else "tun0 interface is still present",
        )
    )

    routes = _run(["ip", "route", "show"])
    securewave_routes = [
        line
        for line in routes.stdout.splitlines()
        if (
            WIREGUARD_INTERFACE in line
            or "securewave" in line
            or "tun0" in line
            or line.startswith(("0.0.0.0/1 ", "128.0.0.0/1 "))
        )
    ]
    checks.append(
        Check(
            "residue:tunnel_routes",
            routes.returncode == 0 and not securewave_routes,
            "no SecureWave/tun split routes"
            if routes.returncode == 0 and not securewave_routes
            else "\n".join(securewave_routes) or routes.stderr.strip() or "ip route failed",
        )
    )

    procs = _run(["pgrep", "-af", "securewave-openvpn|openvpn.*securewave"])
    checks.append(
        Check(
            "residue:openvpn_process",
            procs.returncode != 0,
            "no SecureWave OpenVPN process"
            if procs.returncode != 0
            else procs.stdout.strip(),
        )
    )

    sas = _run(["swanctl", "--list-sas"])
    securewave_sas = [line for line in sas.stdout.splitlines() if "securewave" in line]
    checks.append(
        Check(
            "residue:ikev2_sa",
            not securewave_sas,
            "no SecureWave IKEv2 SA"
            if not securewave_sas
            else "\n".join(securewave_sas),
        )
    )

    active = _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"])
    active_ikev2 = [
        line
        for line in active.stdout.splitlines()
        if line == f"{IKEV2_CONNECTION}:vpn"
    ]
    checks.append(
        Check(
            "residue:ikev2_nm_connection",
            active.returncode == 0 and not active_ikev2,
            f"no active {IKEV2_CONNECTION} NetworkManager VPN"
            if active.returncode == 0 and not active_ikev2
            else "\n".join(active_ikev2) or active.stderr.strip() or "nmcli active connection check failed",
        )
    )

    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()

    checks = [
        *check_tools(),
        check_privilege_elevation(),
        *check_runner_contract(),
        check_build_artifact(),
        *check_residue(),
    ]
    payload = {
        "ok": all(check.ok for check in checks),
        "checks": [check.as_dict() for check in checks],
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for check in checks:
            status = "OK" if check.ok else "FAIL"
            print(f"{status} {check.name}: {check.detail}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
