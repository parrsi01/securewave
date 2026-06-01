#!/usr/bin/env python3
"""Run app-driven Linux VPN tunnel proof for WireGuard, OpenVPN, and IKEv2.

This script drives the Flutter app's real runtime service path through
lib/runtime_vpn_probe.dart. It requires an existing live account because the
native app path fetches real backend profiles before starting tunnels.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "securewave_app"
PROBE_TARGET = "lib/runtime_vpn_probe.dart"
DEFAULT_PROTOCOLS = ("wireguard", "openvpn", "ikev2")
WIREGUARD_INTERFACE = "sw-wg"
PLACEHOLDER_VALUES = {
    "existing-live-email",
    "existing-live-password",
    "real@email.com",
    "real-password",
}
AUTH_FAILURE_MARKERS = (
    "ApiClient.login",
    "ApiClient.register",
    "status code of 401",
    "status code of 422",
    "status code of 429",
)


def _dart_define(name: str, value: object) -> str:
    return "--dart-define=" + name + "=" + str(value)


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str

    def as_dict(self) -> dict[str, object]:
        return {
            "returncode": self.returncode,
            "stdout": self.stdout.strip(),
            "stderr": self.stderr.strip(),
        }


def _run(argv: Iterable[str], *, timeout: int = 15) -> CommandResult:
    completed = subprocess.run(
        list(argv),
        cwd=REPO_ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    return CommandResult(
        completed.returncode,
        completed.stdout,
        completed.stderr,
    )


def _evidence_for(protocol: str) -> dict[str, object]:
    if protocol == "wireguard":
        link = _run(["ip", "link", "show", WIREGUARD_INTERFACE])
        route = _run(["ip", "route", "get", "1.1.1.1"])
        route_ok = route.returncode == 0 and f" dev {WIREGUARD_INTERFACE}" in route.stdout
        return {
            "ok": link.returncode == 0 and route_ok,
            "interface": link.as_dict(),
            "route": route.as_dict(),
        }
    if protocol == "openvpn":
        tun0 = _run(["ip", "link", "show", "tun0"])
        route = _run(["ip", "route", "get", "1.1.1.1"])
        procs = _run(["pgrep", "-af", "securewave-openvpn|openvpn.*securewave"])
        route_ok = route.returncode == 0 and " dev tun" in route.stdout
        return {
            "ok": tun0.returncode == 0 and route_ok and procs.returncode == 0,
            "interface": tun0.as_dict(),
            "route": route.as_dict(),
            "process": procs.as_dict(),
        }
    if protocol == "ikev2":
        sas = _run(["swanctl", "--list-sas"])
        return {
            "ok": sas.returncode == 0 and "securewave" in sas.stdout,
            "sas": sas.as_dict(),
        }
    raise ValueError(f"unsupported protocol: {protocol}")


def _json_line(line: str) -> dict[str, object] | None:
    line = line.strip()
    if not line.startswith("{"):
        return None
    try:
        parsed = json.loads(line)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _json_object(text: str) -> dict[str, object] | None:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _new_probe_credentials() -> tuple[str, str]:
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    suffix = secrets.token_hex(3)
    return (
        f"securewave.runtime.{stamp}.{suffix}@gmail.com",
        f"SwRuntime{secrets.token_hex(4)}!A1",
    )


def _is_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    return value.strip().lower() in PLACEHOLDER_VALUES


def _has_auth_failure(result: dict[str, object]) -> bool:
    events = result.get("probe_events")
    if not isinstance(events, list):
        return False
    for event in events:
        if not isinstance(event, dict):
            continue
        if event.get("event") != "runtime_probe_error":
            continue
        text = f"{event.get('error', '')}\n{event.get('stack', '')}"
        if any(marker in text for marker in AUTH_FAILURE_MARKERS):
            return True
    return False


def run_protocol(
    *,
    protocol: str,
    email: str,
    password: str,
    auth_mode: str,
    server_id: str | None,
    hold_seconds: int,
    evidence_timeout: int,
) -> dict[str, object]:
    command = [
        "flutter",
        "run",
        "-d",
        "linux",
        "-t",
        PROBE_TARGET,
        _dart_define("SECUREWAVE_RUNTIME_PROBE_EMAIL", email),
        _dart_define("SECUREWAVE_RUNTIME_PROBE_PASSWORD", password),
        _dart_define("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", auth_mode),
        _dart_define("SECUREWAVE_RUNTIME_PROBE_PROTOCOL", protocol),
        _dart_define("SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS", hold_seconds),
        _dart_define("SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER", "true"),
    ]
    if server_id:
        command.append(_dart_define("SECUREWAVE_RUNTIME_PROBE_SERVER_ID", server_id))

    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    started_at = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=APP_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )

    output: list[str] = []
    probe_events: list[dict[str, object]] = []
    evidence: dict[str, object] | None = None

    assert process.stdout is not None
    try:
        while True:
            line = process.stdout.readline()
            if line:
                output.append(line.rstrip())
                event = _json_line(line)
                if event is not None:
                    probe_events.append(event)
                    if event.get("event") == "holding_for_evidence":
                        evidence = _evidence_for(protocol)
                if process.poll() is not None:
                    break
            elif process.poll() is not None:
                break

            if evidence is None and time.monotonic() - started_at > evidence_timeout:
                evidence = {
                    "ok": False,
                    "error": f"no holding_for_evidence event within {evidence_timeout}s",
                }
                process.terminate()
                break
    finally:
        try:
            returncode = process.wait(timeout=max(hold_seconds + 30, 45))
        except subprocess.TimeoutExpired:
            process.kill()
            returncode = process.wait(timeout=10)

    while True:
        line = process.stdout.readline()
        if not line:
            break
        output.append(line.rstrip())
        event = _json_line(line)
        if event is not None:
            probe_events.append(event)

    if evidence is None:
        evidence = {"ok": False, "error": "probe exited before evidence window"}

    return {
        "protocol": protocol,
        "ok": returncode == 0 and bool(evidence.get("ok")),
        "returncode": returncode,
        "probe_events": probe_events,
        "evidence": evidence,
        "output_tail": output[-80:],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--email", default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_EMAIL"))
    parser.add_argument("--password", default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_PASSWORD"))
    parser.add_argument(
        "--auth-mode",
        choices=("login", "register", "auto"),
        default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", "auto"),
        help="login uses an existing account; register creates the supplied account; auto creates a disposable QA account when credentials are absent or placeholder values",
    )
    parser.add_argument("--server-id", default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_SERVER_ID"))
    parser.add_argument("--protocol", action="append", choices=DEFAULT_PROTOCOLS)
    parser.add_argument("--hold-seconds", type=int, default=20)
    parser.add_argument("--evidence-timeout", type=int, default=90)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    email = args.email
    password = args.password
    auth_mode = args.auth_mode
    if auth_mode == "auto":
        if _is_placeholder(email) or _is_placeholder(password):
            email, password = _new_probe_credentials()
            auth_mode = "register"
        else:
            auth_mode = "login"
    if not email or not password:
        email, password = _new_probe_credentials()
        auth_mode = "register"

    baseline = _run([sys.executable, "scripts/linux_vpn_runtime_verifier.py", "--json"], timeout=30)
    baseline_body = _json_object(baseline.stdout)
    if baseline.returncode != 0:
        cleanup = _run([sys.executable, "scripts/linux_vpn_runtime_verifier.py", "--json"], timeout=30)
        payload = {
            "ok": False,
            "account_email": email,
            "auth_mode": auth_mode,
            "baseline": baseline.as_dict(),
            "baseline_checks": baseline_body,
            "results": [],
            "cleanup": cleanup.as_dict(),
        }
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print("FAIL baseline")
        return 1

    protocols = args.protocol or list(DEFAULT_PROTOCOLS)
    results = []
    for index, protocol in enumerate(protocols):
        protocol_auth_mode = "login" if auth_mode == "register" and index > 0 else auth_mode
        result = run_protocol(
            protocol=protocol,
            email=email,
            password=password,
            auth_mode=protocol_auth_mode,
            server_id=args.server_id,
            hold_seconds=args.hold_seconds,
            evidence_timeout=args.evidence_timeout,
        )
        results.append(result)
        if _has_auth_failure(result):
            break
    cleanup = _run([sys.executable, "scripts/linux_vpn_runtime_verifier.py", "--json"], timeout=30)
    payload = {
        "ok": all(result["ok"] for result in results) and cleanup.returncode == 0,
        "account_email": email,
        "auth_mode": auth_mode,
        "baseline": baseline.as_dict(),
        "results": results,
        "cleanup": cleanup.as_dict(),
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for result in results:
            status = "OK" if result["ok"] else "FAIL"
            print(f"{status} {result['protocol']}")
        print("OK cleanup" if cleanup.returncode == 0 else "FAIL cleanup")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
