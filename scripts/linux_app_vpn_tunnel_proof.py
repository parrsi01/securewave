#!/usr/bin/env python3
"""Run app-driven Linux VPN tunnel proof for SecureWave Linux tunnels.

This script drives the Flutter app's real runtime service path through
lib/runtime_vpn_probe.dart. It requires an existing live account because the
native app path fetches real backend profiles before starting tunnels.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import select
import signal
import socket
import subprocess  # nosec B404
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "securewave_app"
PROBE_TARGET = "lib/runtime_vpn_probe.dart"
DEFAULT_AUTH_FILE = REPO_ROOT / "securewave_private" / "live_certification_account.env"
SUPPORTED_PROTOCOLS = ("wireguard", "openvpn", "ikev2")
DEFAULT_PROTOCOLS = ("wireguard", "openvpn")
DEFAULT_API_BASE = "https://api.securewaveapp.com/api"
WIREGUARD_INTERFACE = "sw-wg"
IKEV2_CONNECTION = "SecureWave-IKEv2"
HELPER_SOCKET = Path("/run/securewave/helper.sock")
DATA_PLANE_TEST_IPS = ("1.1.1.1", "9.9.9.9")
DNS_TEST_HOSTS = ("example.com", "api.ipify.org")
EXIT_IP_URLS = (
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
)
PLACEHOLDER_VALUES = {
    "existing-live-email",
    "existing-live-password",
    "real@email.com",
    "real-password",
    "your@email.com",
    "your-password",
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


def _run(argv: Iterable[str], *, timeout: float = 15) -> CommandResult:
    command = list(argv)
    try:
        completed = subprocess.run(  # nosec B603
            command,
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
    except FileNotFoundError as exc:
        return CommandResult(127, "", str(exc))
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        detail = f"command timed out after {timeout}s"
        return CommandResult(124, stdout, (stderr + "\n" + detail).strip())


def _remaining_timeout(deadline: float | None, requested: float) -> float:
    if deadline is None:
        return requested
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return 0
    return max(0.25, min(requested, remaining))


def _run_with_budget(
    argv: Iterable[str],
    *,
    timeout: float,
    deadline: float | None,
) -> CommandResult:
    bounded_timeout = _remaining_timeout(deadline, timeout)
    if bounded_timeout <= 0:
        return CommandResult(124, "", "evidence timeout exhausted")
    return _run(argv, timeout=bounded_timeout)


def _attempt(argv: list[str], result: CommandResult) -> dict[str, object]:
    return {
        "command": argv,
        "result": result.as_dict(),
    }


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")


def _unescape(value: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(value):
        if value[i] != "\\" or i + 1 >= len(value):
            out.append(value[i])
            i += 1
            continue
        i += 1
        if value[i] == "n":
            out.append("\n")
        elif value[i] == "r":
            out.append("\r")
        else:
            out.append(value[i])
        i += 1
    return "".join(out)


def _helper_request(fields: dict[str, str], timeout: float = 20.0) -> dict[str, str]:
    request = {"version": "1", **fields}
    body = "".join(f"{key}={_escape(value)}\n" for key, value in request.items())
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(str(HELPER_SOCKET))
        client.sendall(body.encode("utf-8"))
        client.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    response: dict[str, str] = {}
    for line in b"".join(chunks).decode("utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        response[key] = _unescape(value)
    return response


def _helper_evidence(fields: dict[str, str], timeout: float = 20.0) -> dict[str, object]:
    try:
        response = _helper_request(fields, timeout=timeout)
    except OSError as exc:
        return {
            "ok": False,
            "error": str(exc),
            "response": {"ok": "false", "code": "socket_error", "message": str(exc)},
        }
    ok = response.get("ok") == "true"
    return {"ok": ok, "response": response}


def _state_path(filename: str) -> str:
    return str(Path.home() / ".config" / "securewave" / filename)


def _cleanup_protocol_residue(protocol: str) -> list[dict[str, object]]:
    requests: list[dict[str, str]] = []
    if protocol == "wireguard":
        requests.append({"op": "wireguard.cleanup", "config_path": _state_path("sw-wg.conf")})
    elif protocol == "openvpn":
        requests.append(
            {
                "op": "openvpn.cleanup",
                "pid_path": _state_path("securewave-openvpn.pid"),
                "log_path": _state_path("securewave-openvpn.log"),
            }
        )
    elif protocol == "ikev2":
        requests.append({"op": "ikev2.cleanup"})

    actions: list[dict[str, object]] = []
    for request in requests:
        try:
            response = _helper_request(request)
        except OSError as exc:
            response = {"ok": "false", "code": "socket_error", "message": str(exc)}
        actions.append({"protocol": protocol, "request": request, "response": response})
    return actions


def _health_url(api_base: str | None) -> str:
    return (api_base or DEFAULT_API_BASE).rstrip("/") + "/health"


def _backend_health_evidence(api_base: str | None, *, timeout: float = 15.0) -> dict[str, object]:
    url = _health_url(api_base)
    if timeout <= 0:
        return {
            "ok": False,
            "url": url,
            "elapsed_ms": 0,
            "error": "evidence timeout exhausted",
        }
    request = urllib.request.Request(url, headers={"User-Agent": "SecureWaveLinuxProof/1"})
    started_at = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # nosec B310
            body = response.read(4096).decode("utf-8", errors="replace").strip()
            status = getattr(response, "status", response.getcode())
            return {
                "ok": 200 <= int(status) < 300,
                "url": url,
                "status": int(status),
                "elapsed_ms": int((time.monotonic() - started_at) * 1000),
                "body": body,
            }
    except urllib.error.HTTPError as exc:
        body = exc.read(4096).decode("utf-8", errors="replace").strip()
        return {
            "ok": False,
            "url": url,
            "status": exc.code,
            "elapsed_ms": int((time.monotonic() - started_at) * 1000),
            "body": body,
        }
    except Exception as exc:  # noqa: BLE001 - proof output should preserve the exact failure.
        return {
            "ok": False,
            "url": url,
            "elapsed_ms": int((time.monotonic() - started_at) * 1000),
            "error": str(exc),
        }


def _data_plane_evidence(deadline: float | None = None) -> dict[str, object]:
    attempts: list[dict[str, object]] = []
    for ip in DATA_PLANE_TEST_IPS:
        command = [
            "curl",
            "-4",
            "-m",
            "5",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}\\n",
            f"https://{ip}",
        ]
        result = _run_with_budget(command, timeout=6, deadline=deadline)
        attempts.append(_attempt(command, result))
        if result.returncode == 0:
            return {
                "ok": True,
                "selected_ip": ip,
                "attempts": attempts,
            }
    return {
        "ok": False,
        "error_kind": "data_plane_unreachable",
        "attempts": attempts,
    }


def _dns_evidence(deadline: float | None = None) -> dict[str, object]:
    attempts: list[dict[str, object]] = []
    for host in DNS_TEST_HOSTS:
        command = ["dig", "+time=3", "+tries=1", "+short", host, "A"]
        result = _run_with_budget(command, timeout=5, deadline=deadline)
        attempts.append(_attempt(command, result))
        answers = [
            line.strip()
            for line in result.stdout.splitlines()
            if line.strip() and not line.lstrip().startswith(";")
        ]
        if result.returncode == 0 and answers:
            return {
                "ok": True,
                "hostname": host,
                "answers": answers,
                "attempts": attempts,
            }
    return {
        "ok": False,
        "error_kind": "dns_broken_in_tunnel",
        "attempts": attempts,
    }


def _extract_ipv4(value: str) -> str | None:
    for raw in value.replace(",", " ").split():
        token = raw.strip()
        try:
            address = ipaddress.ip_address(token)
        except ValueError:
            continue
        if address.version == 4:
            return str(address)
    return None


def _exit_ip_lookup(deadline: float | None = None) -> dict[str, object]:
    attempts: list[dict[str, object]] = []
    for url in EXIT_IP_URLS:
        command = ["curl", "-4", "-m", "8", "-fsS", url]
        result = _run_with_budget(command, timeout=9, deadline=deadline)
        attempts.append(_attempt(command, result))
        ip = _extract_ipv4(result.stdout)
        if result.returncode == 0 and ip:
            return {
                "ok": True,
                "ip": ip,
                "url": url,
                "attempts": attempts,
            }
    return {
        "ok": False,
        "ip": None,
        "error_kind": "exit_ip_unavailable",
        "attempts": attempts,
    }


def _exit_ip_evidence(
    pre_connect_exit_ip: dict[str, object] | None,
    deadline: float | None = None,
) -> dict[str, object]:
    pre_connect = pre_connect_exit_ip or {
        "ok": False,
        "ip": None,
        "error_kind": "exit_ip_unavailable",
        "attempts": [],
    }
    connected = _exit_ip_lookup(deadline=deadline)
    evidence = {
        "ok": False,
        "pre_connect": pre_connect,
        "connected": connected,
        "pre_connect_ip": pre_connect.get("ip"),
        "connected_ip": connected.get("ip"),
    }
    if not pre_connect.get("ok") or not connected.get("ok"):
        evidence["error_kind"] = "exit_ip_unavailable"
        return evidence
    if pre_connect.get("ip") == connected.get("ip"):
        evidence["error_kind"] = "exit_ip_unchanged"
        return evidence
    evidence["ok"] = True
    return evidence


def _ikev2_routing_rule_evidence(deadline: float | None = None) -> dict[str, object]:
    command = ["ip", "rule"]
    result = _run_with_budget(command, timeout=5, deadline=deadline)
    bad_rules: list[str] = []
    for raw_line in result.stdout.splitlines():
        line = " ".join(raw_line.split())
        if (
            line.startswith("220:")
            and "from all" in line
            and "lookup 220" in line
            and "fwmark" not in line
        ):
            bad_rules.append(raw_line.strip())
    return {
        "ok": result.returncode == 0 and not bad_rules,
        "error_kind": "ikev2_routing_loop_rule" if bad_rules else None,
        "bad_rules": bad_rules,
        "ip_rule": _attempt(command, result),
    }


def _wireguard_counter_evidence() -> dict[str, object]:
    result = _helper_evidence({"op": "wireguard.counters"})
    response = result.get("response")
    stdout = response.get("stdout", "") if isinstance(response, dict) else ""
    return {
        "ok": bool(result.get("ok")) and bool(stdout.strip()),
        "response": response,
    }


def _tun_interface_evidence() -> dict[str, object]:
    links = _run(["ip", "-o", "link", "show"])
    interfaces: list[str] = []
    if links.returncode == 0:
        for line in links.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) < 2:
                continue
            name = parts[1].strip().split("@", 1)[0]
            if name.startswith("tun"):
                interfaces.append(name)
    return {
        "ok": links.returncode == 0 and bool(interfaces),
        "interfaces": interfaces,
        "links": links.as_dict(),
    }


def _openvpn_log_evidence() -> dict[str, object]:
    path = Path(_state_path("securewave-openvpn.log"))
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        return {"ok": False, "path": str(path), "error": str(exc)}
    success = any("Initialization Sequence Completed" in line for line in lines)
    return {
        "ok": success,
        "path": str(path),
        "tail": [line.strip() for line in lines[-12:] if line.strip()],
    }


def _runtime_evidence_for(
    protocol: str,
    api_base: str | None,
    deadline: float | None = None,
) -> dict[str, object]:
    if protocol == "wireguard":
        link = _run(["ip", "link", "show", WIREGUARD_INTERFACE])
        route = _run(["ip", "route", "get", "1.1.1.1"])
        route_ok = route.returncode == 0 and f" dev {WIREGUARD_INTERFACE}" in route.stdout
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        counters = _wireguard_counter_evidence()
        return {
            "ok": link.returncode == 0 and route_ok and bool(backend_health.get("ok")) and bool(counters.get("ok")),
            "interface": link.as_dict(),
            "route": route.as_dict(),
            "backend_health": backend_health,
            "traffic_counters": counters,
        }
    if protocol == "openvpn":
        tun = _tun_interface_evidence()
        route = _run(["ip", "route", "get", "1.1.1.1"])
        procs = _run(["pgrep", "-x", "openvpn"])
        route_ok = route.returncode == 0 and " dev tun" in route.stdout
        log = _openvpn_log_evidence()
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        return {
            "ok": bool(tun.get("ok"))
            and route_ok
            and procs.returncode == 0
            and bool(log.get("ok"))
            and bool(backend_health.get("ok")),
            "interface": tun,
            "route": route.as_dict(),
            "process": procs.as_dict(),
            "log": log,
            "backend_health": backend_health,
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
        helper_status = _helper_evidence({"op": "ikev2.status"})
        helper_response = helper_status.get("response")
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        active_ok = active.returncode == 0 and f"{IKEV2_CONNECTION}:vpn" in active.stdout.splitlines()
        route_dns_ok = route_dns.returncode == 0 and any(
            line.partition(":")[2].strip() not in ("", "--")
            for line in route_dns.stdout.splitlines()
            if ":" in line
        )
        xfrm_ok = (
            bool(helper_status.get("ok"))
            and isinstance(helper_response, dict)
            and helper_response.get("status") == "connected"
        )
        return {
            "ok": active_ok and route_dns_ok and xfrm_ok and bool(backend_health.get("ok")),
            "active_connection": active.as_dict(),
            "route_dns": route_dns.as_dict(),
            "helper_status": helper_status,
            "backend_health": backend_health,
        }
    raise ValueError(f"unsupported protocol: {protocol}")


def _failed_network_evidence(
    *,
    error_kind: str,
    data_plane: dict[str, object],
    dns: dict[str, object] | None = None,
    exit_ip: dict[str, object] | None = None,
    ikev2_routing_rule: dict[str, object] | None = None,
) -> dict[str, object]:
    evidence: dict[str, object] = {
        "ok": False,
        "error_kind": error_kind,
        "data_plane": data_plane,
    }
    if dns is not None:
        evidence["dns"] = dns
    if exit_ip is not None:
        evidence["exit_ip"] = exit_ip
    if ikev2_routing_rule is not None:
        evidence["ikev2_routing_rule"] = ikev2_routing_rule
    return evidence


def _evidence_for(
    protocol: str,
    api_base: str | None,
    *,
    pre_connect_exit_ip: dict[str, object] | None = None,
    evidence_deadline: float | None = None,
) -> dict[str, object]:
    data_plane = _data_plane_evidence(deadline=evidence_deadline)
    if not data_plane.get("ok"):
        return _failed_network_evidence(
            error_kind="data_plane_unreachable",
            data_plane=data_plane,
        )

    dns = _dns_evidence(deadline=evidence_deadline)
    if not dns.get("ok"):
        return _failed_network_evidence(
            error_kind="dns_broken_in_tunnel",
            data_plane=data_plane,
            dns=dns,
        )

    exit_ip = _exit_ip_evidence(pre_connect_exit_ip, deadline=evidence_deadline)
    if not exit_ip.get("ok"):
        return _failed_network_evidence(
            error_kind=str(exit_ip.get("error_kind") or "exit_ip_unavailable"),
            data_plane=data_plane,
            dns=dns,
            exit_ip=exit_ip,
        )

    ikev2_routing_rule = None
    if protocol == "ikev2":
        ikev2_routing_rule = _ikev2_routing_rule_evidence(deadline=evidence_deadline)
        if not ikev2_routing_rule.get("ok"):
            return _failed_network_evidence(
                error_kind="ikev2_routing_loop_rule",
                data_plane=data_plane,
                dns=dns,
                exit_ip=exit_ip,
                ikev2_routing_rule=ikev2_routing_rule,
            )

    runtime = _runtime_evidence_for(protocol, api_base, deadline=evidence_deadline)
    runtime.update(
        {
            "data_plane": data_plane,
            "dns": dns,
            "exit_ip": exit_ip,
        }
    )
    if ikev2_routing_rule is not None:
        runtime["ikev2_routing_rule"] = ikev2_routing_rule
    if not runtime.get("ok"):
        runtime.setdefault("error_kind", "protocol_evidence_failed")
    return runtime


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


def _probe_error_evidence(event: dict[str, object]) -> dict[str, object]:
    error = event.get("error")
    return {
        "ok": False,
        "error": str(error or "runtime_probe_error"),
        "event": event,
    }


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
    pre_connect_exit_ip = _exit_ip_lookup(deadline=time.monotonic() + 20)

    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    started_at = time.monotonic()
    evidence_deadline = started_at + evidence_timeout
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
                            evidence = _evidence_for(
                                protocol,
                                api_base,
                                pre_connect_exit_ip=pre_connect_exit_ip,
                                evidence_deadline=evidence_deadline,
                            )
                        elif event.get("event") == "runtime_probe_error":
                            evidence = _probe_error_evidence(event)
                            _stop_process_group(process)
                            break
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
        "pre_connect_exit_ip": pre_connect_exit_ip,
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
    parser.add_argument("--protocol", action="append", choices=SUPPORTED_PROTOCOLS)
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
    protocols = args.protocol or list(DEFAULT_PROTOCOLS)
    preflight_cleanup_actions: list[dict[str, object]] = []
    for protocol in protocols:
        preflight_cleanup_actions.extend(_cleanup_protocol_residue(protocol))

    baseline = _run(
        [
            sys.executable,
            "scripts/linux_vpn_runtime_verifier.py",
            "--json",
        ],
        timeout=30,
    )
    baseline_body = _json_object(baseline.stdout)
    if baseline.returncode != 0:
        cleanup = _run(
            [
                sys.executable,
                "scripts/linux_vpn_runtime_verifier.py",
                "--json",
            ],
            timeout=30,
        )
        payload = {
            "ok": False,
            "account_email": _redact_email(email),
            "auth_mode": auth_mode,
            "preflight_cleanup_actions": preflight_cleanup_actions,
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
        cleanup_actions.extend(_cleanup_protocol_residue(protocol))
        if _has_auth_failure(result):
            break
    cleanup = _run(
        [
            sys.executable,
            "scripts/linux_vpn_runtime_verifier.py",
            "--json",
        ],
        timeout=30,
    )
    payload = {
        "ok": all(result["ok"] for result in results) and cleanup.returncode == 0,
        "account_email": _redact_email(email),
        "auth_mode": auth_mode,
        "preflight_cleanup_actions": preflight_cleanup_actions,
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
