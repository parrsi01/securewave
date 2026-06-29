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
import select
import signal
import subprocess  # nosec B404
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "securewave_app"
PROBE_TARGET = "lib/runtime_vpn_probe.dart"
DEFAULT_AUTH_FILE = REPO_ROOT / "securewave_private" / "live_certification_account.env"
DEFAULT_PROTOCOLS = ("wireguard", "openvpn", "ikev2")
DEFAULT_API_BASE = "https://api.securewaveapp.com/api"
WIREGUARD_INTERFACE = "sw-wg"
IKEV2_CONNECTION = "SecureWave-IKEv2"
SECUREWAVE_HELPER = "/usr/local/libexec/securewave-wg-quick"
PLACEHOLDER_VALUES = {
    "existing-live-email",
    "existing-live-password",
    "real@email.com",
    "real-password",
    "your-real-test-account@example.com",
    "your-real-test-password",
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


def _env_default(*names: str) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None


def _parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("export "):
            stripped = stripped[len("export ") :].strip()
        if "=" not in stripped:
            continue
        key, raw_value = stripped.split("=", 1)
        key = key.strip()
        if key not in {
            "DEMO_EMAIL",
            "DEMO_PASSWORD",
            "SECUREWAVE_TEST_EMAIL",
            "SECUREWAVE_TEST_PASSWORD",
            "SECUREWAVE_RUNTIME_PROBE_EMAIL",
            "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
        }:
            continue
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def _credential_file_path(auth_file: str | None) -> Path | None:
    if auth_file:
        return Path(auth_file).expanduser()
    return DEFAULT_AUTH_FILE if DEFAULT_AUTH_FILE.is_file() else None


def _file_default(values: dict[str, str], *names: str) -> str | None:
    for name in names:
        value = values.get(name)
        if value:
            return value
    return None


def _redact_email(email: str) -> str:
    local, separator, domain = email.partition("@")
    if not separator:
        return "configured"
    prefix = local[:1] if local else "*"
    return f"{prefix}***@{domain}"


def _default_api_base() -> str:
    return _env_default("SECUREWAVE_API_BASE_URL") or DEFAULT_API_BASE


def _build_flutter_command(
    *,
    protocol: str,
    email: str,
    password: str,
    auth_mode: str,
    server_id: str | None,
    hold_seconds: int,
    api_base: str | None,
    use_mock_api: str,
) -> list[str]:
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
        _dart_define("SECUREWAVE_USE_MOCK_API", use_mock_api),
    ]
    if api_base:
        command.append(_dart_define("SECUREWAVE_API_BASE_URL", api_base))
    if server_id:
        command.append(_dart_define("SECUREWAVE_RUNTIME_PROBE_SERVER_ID", server_id))
    return command


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
    completed = subprocess.run(  # nosec B603
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


def _securewave_helper_command(action: str) -> list[str]:
    command = [SECUREWAVE_HELPER, action]
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return command
    return ["pkexec", "--disable-internal-agent", *command]


def _cleanup_protocol_residue(protocol: str, pkexec_timeout: int) -> list[dict[str, object]]:
    commands: list[list[str]] = []
    if protocol == "wireguard":
        commands.append([*_securewave_helper_command("policy-clear-link"), WIREGUARD_INTERFACE])
    elif protocol == "ikev2":
        commands.append(_securewave_helper_command("ikev2-down"))
        commands.append(_securewave_helper_command("ikev2-delete"))

    return [
        {
            "protocol": protocol,
            "command": command,
            "result": _run(command, timeout=max(pkexec_timeout, 15)).as_dict(),
        }
        for command in commands
    ]


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
        procs = _run(["pgrep", "-x", "openvpn"])
        route_ok = route.returncode == 0 and " dev tun" in route.stdout
        return {
            "ok": tun0.returncode == 0 and route_ok and procs.returncode == 0,
            "interface": tun0.as_dict(),
            "route": route.as_dict(),
            "process": procs.as_dict(),
        }
    if protocol == "ikev2":
        active = _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"])
        route_dns = _run([
            "nmcli",
            "-t",
            "-f",
            "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE",
            "connection",
            "show",
            IKEV2_CONNECTION,
        ])
        xfrm_state = _run(_securewave_helper_command("xfrm-state"))
        active_ok = active.returncode == 0 and f"{IKEV2_CONNECTION}:vpn" in active.stdout.splitlines()
        route_dns_ok = route_dns.returncode == 0 and any(
            line.partition(":")[2].strip() not in ("", "--")
            for line in route_dns.stdout.splitlines()
            if ":" in line
        )
        xfrm_ok = xfrm_state.returncode == 0 and "proto esp" in xfrm_state.stdout
        return {
            "ok": active_ok and route_dns_ok and xfrm_ok,
            "active_connection": active.as_dict(),
            "route_dns": route_dns.as_dict(),
            "xfrm_state": xfrm_state.as_dict(),
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


def _is_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    return value.strip().lower() in PLACEHOLDER_VALUES


def _credential_error(email: str | None, password: str | None) -> str | None:
    if email is None or not email.strip() or password is None or not password.strip():
        return (
            "existing live account credentials are required via --email/--password, "
            "DEMO_EMAIL/DEMO_PASSWORD, SECUREWAVE_TEST_EMAIL/SECUREWAVE_TEST_PASSWORD, or "
            "SECUREWAVE_RUNTIME_PROBE_EMAIL/SECUREWAVE_RUNTIME_PROBE_PASSWORD; "
            "SECUREWAVE_CERT_AUTH_FILE may point to a local key-value credential file"
        )
    if _is_placeholder(email) or _is_placeholder(password):
        return (
            "placeholder live account credentials are not valid for certification; "
            "configure a stable existing test account"
        )
    return None


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


def _stop_process_group(process: subprocess.Popen[str], *, force: bool = False) -> None:
    sig = signal.SIGKILL if force else signal.SIGTERM
    try:
        os.killpg(os.getpgid(process.pid), sig)
    except ProcessLookupError:
        return
    except Exception:
        if force:
            process.kill()
        else:
            process.terminate()


def _drain_available_stdout(
    process: subprocess.Popen[str],
    output: list[str],
    probe_events: list[dict[str, object]],
) -> None:
    if process.stdout is None:
        return
    while True:
        ready, _, _ = select.select([process.stdout], [], [], 0)
        if not ready:
            break
        line = process.stdout.readline()
        if not line:
            break
        output.append(line.rstrip())
        event = _json_line(line)
        if event is not None:
            probe_events.append(event)


def run_protocol(
    *,
    protocol: str,
    email: str,
    password: str,
    auth_mode: str,
    server_id: str | None,
    hold_seconds: int,
    evidence_timeout: int,
    api_base: str | None,
    use_mock_api: str,
) -> dict[str, object]:
    command = _build_flutter_command(
        protocol=protocol,
        email=email,
        password=password,
        auth_mode=auth_mode,
        server_id=server_id,
        hold_seconds=hold_seconds,
        api_base=api_base,
        use_mock_api=use_mock_api,
    )

    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    started_at = time.monotonic()
    process = subprocess.Popen(  # nosec B603
        command,
        cwd=APP_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        start_new_session=True,
    )

    output: list[str] = []
    probe_events: list[dict[str, object]] = []
    evidence: dict[str, object] | None = None

    if process.stdout is None:
        process.kill()
        raise RuntimeError("Flutter process stdout pipe was not created.")
    try:
        while True:
            ready, _, _ = select.select([process.stdout], [], [], 0.25)
            if ready:
                line = process.stdout.readline()
                if line:
                    output.append(line.rstrip())
                    event = _json_line(line)
                    if event is not None:
                        probe_events.append(event)
                        if event.get("event") == "holding_for_evidence":
                            evidence = _evidence_for(protocol)
                elif process.poll() is not None:
                    break
            if process.poll() is not None:
                break

            if evidence is None and time.monotonic() - started_at > evidence_timeout:
                evidence = {
                    "ok": False,
                    "error": f"no holding_for_evidence event within {evidence_timeout}s",
                }
                _stop_process_group(process)
                break
    finally:
        try:
            returncode = process.wait(timeout=max(hold_seconds + 30, 45))
        except subprocess.TimeoutExpired:
            _stop_process_group(process, force=True)
            returncode = process.wait(timeout=10)

    _drain_available_stdout(process, output, probe_events)

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
    parser.add_argument(
        "--email",
        default=_env_default(
            "DEMO_EMAIL",
            "SECUREWAVE_TEST_EMAIL",
            "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        ),
    )
    parser.add_argument(
        "--password",
        default=_env_default(
            "DEMO_PASSWORD",
            "SECUREWAVE_TEST_PASSWORD",
            "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
        ),
    )
    parser.add_argument(
        "--auth-mode",
        choices=("login", "register", "auto"),
        default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", "login"),
        help=(
            "login uses an existing account; register creates the supplied account; "
            "auto is retained for compatibility and resolves to login without "
            "generating disposable credentials"
        ),
    )
    parser.add_argument("--server-id", default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_SERVER_ID"))
    parser.add_argument("--api-base", default=_default_api_base())
    parser.add_argument(
        "--auth-file",
        default=_env_default("SECUREWAVE_CERT_AUTH_FILE", "SECUREWAVE_LIVE_ACCOUNT_FILE"),
        help=(
            "Optional key=value file for stable live credentials. Defaults to "
            "securewave_private/live_certification_account.env when present."
        ),
    )
    parser.add_argument(
        "--use-mock-api",
        default=os.environ.get("SECUREWAVE_USE_MOCK_API", "false"),
    )
    parser.add_argument(
        "--pkexec-timeout",
        type=int,
        default=int(os.environ.get("SECUREWAVE_PKEXEC_TIMEOUT", "60")),
    )
    parser.add_argument("--protocol", action="append", choices=DEFAULT_PROTOCOLS)
    parser.add_argument("--hold-seconds", type=int, default=20)
    parser.add_argument("--evidence-timeout", type=int, default=90)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    credential_values: dict[str, str] = {}
    auth_file_path = _credential_file_path(args.auth_file)
    if auth_file_path is not None:
        if not auth_file_path.is_file():
            payload = {
                "ok": False,
                "account_email": None,
                "auth_mode": args.auth_mode,
                "error": f"credential file does not exist: {auth_file_path}",
                "results": [],
            }
            if args.json:
                print(json.dumps(payload, indent=2, sort_keys=True))
            else:
                print(f"FAIL auth: {payload['error']}")
            return 2
        credential_values = _parse_env_file(auth_file_path)

    email = args.email or _file_default(
        credential_values,
        "DEMO_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    )
    password = args.password or _file_default(
        credential_values,
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
    )
    auth_mode = args.auth_mode
    if auth_mode == "auto":
        auth_mode = "login"
    credential_error = _credential_error(email, password)
    if credential_error:
        payload = {
            "ok": False,
            "account_email": None,
            "auth_mode": auth_mode,
            "error": credential_error,
            "results": [],
        }
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"FAIL auth: {credential_error}")
        return 2
    email = email.strip()
    password = password.strip()
    os.environ.setdefault("SECUREWAVE_PKEXEC_TIMEOUT", str(args.pkexec_timeout))

    baseline = _run(
        [
            sys.executable,
            "scripts/linux_vpn_runtime_verifier.py",
            "--json",
            "--pkexec-timeout",
            str(args.pkexec_timeout),
        ],
        timeout=max(args.pkexec_timeout + 10, 30),
    )
    baseline_body = _json_object(baseline.stdout)
    if baseline.returncode != 0:
        cleanup = _run(
            [
                sys.executable,
                "scripts/linux_vpn_runtime_verifier.py",
                "--json",
                "--pkexec-timeout",
                str(args.pkexec_timeout),
            ],
            timeout=max(args.pkexec_timeout + 10, 30),
        )
        payload = {
            "ok": False,
            "account_email": _redact_email(email),
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
    cleanup_actions: list[dict[str, object]] = []
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
            api_base=args.api_base,
            use_mock_api=args.use_mock_api,
        )
        results.append(result)
        cleanup_actions.extend(_cleanup_protocol_residue(protocol, args.pkexec_timeout))
        if _has_auth_failure(result):
            break
    cleanup = _run(
        [
            sys.executable,
            "scripts/linux_vpn_runtime_verifier.py",
            "--json",
            "--pkexec-timeout",
            str(args.pkexec_timeout),
        ],
        timeout=max(args.pkexec_timeout + 10, 30),
    )
    payload = {
        "ok": all(result["ok"] for result in results) and cleanup.returncode == 0,
        "account_email": _redact_email(email),
        "auth_mode": auth_mode,
        "baseline": baseline.as_dict(),
        "results": results,
        "cleanup_actions": cleanup_actions,
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
