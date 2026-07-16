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
import platform
import re
import select
import shutil
import signal
import socket
import subprocess  # nosec B404
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "securewave_app"
PROBE_TARGET = "lib/runtime_vpn_probe.dart"
DEFAULT_AUTH_FILE = REPO_ROOT / "securewave_private" / "live_certification_account.env"
SHARED_AUTH_RELATIVE_PATH = Path("securewave_private/live_certification_account.env")
SUPPORTED_PROTOCOLS = ("wireguard", "openvpn", "ikev2")
DEFAULT_PROTOCOLS = SUPPORTED_PROTOCOLS
DEFAULT_API_BASE: str | None = None
MINIMUM_HELPER_CONTRACT = 13
RELEASE_PROBE_BUILD_TIMEOUT_SECONDS = 120
PROCESS_TERMINATION_GRACE_SECONDS = 10
LATE_HOLD_EVIDENCE_MAX_LEAD_SECONDS = 15.0
WIREGUARD_INTERFACE = "sw-wg"
OPENVPN_INTERFACE = "tun-securewave"
IKEV2_CONNECTION = "SecureWave-IKEv2"
IKEV2_INTERFACE = "nm-xfrm-sw"
HELPER_SOCKET = Path("/run/securewave/helper.sock")
DATA_PLANE_TEST_IPS = ("1.1.1.1", "9.9.9.9")
DNS_TEST_HOSTS = ("example.com", "api.ipify.org")
EXIT_IP_URLS = (
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
)
IPV6_EXIT_IP_URLS = (
    "https://api6.ipify.org",
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
BUILD_ENVIRONMENT_BLOCKLIST = {
    "DEMO_EMAIL",
    "DEMO_PASSWORD",
    "SECUREWAVE_TEST_EMAIL",
    "SECUREWAVE_TEST_PASSWORD",
    "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
    "SECUREWAVE_RUNTIME_PROBE_AUTH_MODE",
    "SECUREWAVE_RUNTIME_PROBE_PROTOCOL",
    "SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS",
    "SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER",
    "SECUREWAVE_RUNTIME_PROBE_RESET_REFERENCES",
    "SECUREWAVE_RUNTIME_PROBE_ALLOW_UNADVERTISED_OPENVPN",
    "SECUREWAVE_RUNTIME_PROBE_SERVER_ID",
    "SECUREWAVE_CERT_AUTH_FILE",
    "SECUREWAVE_LIVE_ACCOUNT_FILE",
    "SECUREWAVE_API_BASE_URL",
    "SECUREWAVE_USE_MOCK_API",
}
RUNTIME_ENVIRONMENT_ALLOWLIST = {
    "DBUS_SESSION_BUS_ADDRESS",
    "DISPLAY",
    "GDK_BACKEND",
    "HOME",
    "LANG",
    "LC_ALL",
    "LOGNAME",
    "PATH",
    "USER",
    "WAYLAND_DISPLAY",
    "XAUTHORITY",
    "XDG_RUNTIME_DIR",
}
BUILD_ENVIRONMENT_ALLOWLIST = RUNTIME_ENVIRONMENT_ALLOWLIST | {
    "CC",
    "CXX",
    "FLUTTER_ROOT",
    "PKG_CONFIG_PATH",
    "PUB_CACHE",
    "TMPDIR",
}


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
    if DEFAULT_AUTH_FILE.is_file():
        return DEFAULT_AUTH_FILE
    try:
        completed = subprocess.run(  # nosec B603
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd=REPO_ROOT,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    shared_candidate = (
        Path(completed.stdout.strip()).resolve().parent / SHARED_AUTH_RELATIVE_PATH
    )
    return shared_candidate if shared_candidate.is_file() else None


def _credential_file_security_error(path: Path) -> str | None:
    try:
        file_stat = path.stat()
    except OSError as exc:
        return f"credential file cannot be inspected: {type(exc).__name__}"
    if file_stat.st_uid != os.getuid():
        return f"credential file must be owned by the current user: {path}"
    mode = file_stat.st_mode & 0o777
    if mode & 0o077:
        return f"credential file permissions must be owner-only (0600): {path}"
    return None


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


def _redact_sensitive_text(text: str, *, email: str, password: str) -> str:
    redacted = text
    replacements = ((password, "[redacted-password]"), (email, "[redacted-email]"))
    for secret, replacement in replacements:
        if not secret:
            continue
        variants = {
            secret,
            json.dumps(secret)[1:-1],
            urllib.parse.quote(secret, safe=""),
            urllib.parse.quote_plus(secret, safe=""),
        }
        for variant in variants:
            if variant:
                redacted = redacted.replace(variant, replacement)
    return redacted


def _redact_sensitive_value(value: object, *, email: str, password: str) -> object:
    if isinstance(value, str):
        return _redact_sensitive_text(value, email=email, password=password)
    if isinstance(value, list):
        return [
            _redact_sensitive_value(item, email=email, password=password)
            for item in value
        ]
    if isinstance(value, dict):
        return {
            key: _redact_sensitive_value(item, email=email, password=password)
            for key, item in value.items()
        }
    return value


def _default_api_base() -> str | None:
    return os.environ.get("SECUREWAVE_API_BASE_URL", "").strip() or None


def _canonical_api_base(raw: str) -> str:
    value = raw.strip().rstrip("/")
    parsed = urllib.parse.urlsplit(value)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise argparse.ArgumentTypeError(
            "must be an explicit local or staging HTTP(S) API base"
        )
    if parsed.scheme == "http" and host not in {"localhost", "127.0.0.1", "::1"}:
        raise argparse.ArgumentTypeError(
            "plain HTTP is allowed only for loopback local staging"
        )
    allow_production = (
        os.environ.get("SECUREWAVE_ALLOW_PRODUCTION_PROOF", "").strip().lower()
        == "true"
    )
    if host == "api.securewaveapp.com" and not allow_production:
        raise argparse.ArgumentTypeError(
            "production API certification is blocked unless "
            "SECUREWAVE_ALLOW_PRODUCTION_PROOF=true is explicitly set"
        )
    return value


def _sanitized_build_environment() -> dict[str, str]:
    env = {
        name: value
        for name, value in os.environ.items()
        if name in BUILD_ENVIRONMENT_ALLOWLIST
    }
    for name in BUILD_ENVIRONMENT_BLOCKLIST:
        env.pop(name, None)
    env.setdefault("HOME", str(Path.home()))
    env.setdefault("PATH", "/usr/local/bin:/usr/bin:/bin")
    return env


def _build_release_probe(app_root: Path = APP_ROOT) -> CommandResult:
    command = _release_probe_build_command()
    try:
        completed = subprocess.run(  # nosec B603
            command,
            cwd=app_root,
            env=_sanitized_build_environment(),
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=RELEASE_PROBE_BUILD_TIMEOUT_SECONDS,
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
        return CommandResult(
            124,
            stdout,
            (
                stderr
                + "\nrelease probe build timed out after "
                f"{RELEASE_PROBE_BUILD_TIMEOUT_SECONDS}s"
            ).strip(),
        )


def _release_probe_build_command() -> list[str]:
    return ["flutter", "build", "linux", "--release", "-t", PROBE_TARGET]


def _probe_binary_path(app_root: Path = APP_ROOT) -> Path:
    machine = platform.machine().lower()
    architecture = {
        "aarch64": "arm64",
        "arm64": "arm64",
        "amd64": "x64",
        "x86_64": "x64",
    }.get(machine)
    if architecture is None:
        raise RuntimeError(f"unsupported Linux build architecture: {machine}")
    return (
        app_root
        / "build"
        / "linux"
        / architecture
        / "release"
        / "bundle"
        / "securewave_app"
    )


def _prepare_probe_workspace() -> Path:
    workspace = Path(tempfile.mkdtemp(prefix="securewave-runtime-probe-"))
    app_root = workspace / "securewave_app"

    def ignore_generated(path: str, names: list[str]) -> set[str]:
        ignored = {
            name
            for name in names
            if name in {"build", ".dart_tool", ".plugin_symlinks", ".ruff_cache"}
        }
        if Path(path).name.lower() == "flutter":
            ignored.add("ephemeral")
        return ignored

    try:
        shutil.copytree(APP_ROOT, app_root, ignore=ignore_generated)
    except Exception:
        shutil.rmtree(workspace, ignore_errors=True)
        raise
    return app_root


def _remove_probe_workspace(app_root: Path | None) -> dict[str, object]:
    if app_root is None:
        return {"ok": True, "removed": False}
    workspace = app_root.parent
    try:
        shutil.rmtree(workspace)
    except OSError as exc:
        return {
            "ok": False,
            "removed": False,
            "error": f"{type(exc).__name__}: {exc}",
        }
    return {"ok": not workspace.exists(), "removed": not workspace.exists()}


def _build_probe_command(probe_binary: Path) -> list[str]:
    return [str(probe_binary)]


def _build_probe_environment(
    *,
    protocol: str,
    email: str,
    password: str,
    auth_mode: str,
    server_id: str | None,
    hold_seconds: int,
    api_base: str | None,
    use_mock_api: str,
) -> dict[str, str]:
    auth_mode = _login_auth_mode(auth_mode)
    use_mock_api = _disabled_mock_api(use_mock_api)
    raw_api_base = api_base or _default_api_base()
    if not raw_api_base:
        raise ValueError(
            "an explicit --api-base or SECUREWAVE_API_BASE_URL is required; production is never selected implicitly"
        )
    api_base = _canonical_api_base(raw_api_base)
    env = {
        name: value
        for name, value in os.environ.items()
        if name in RUNTIME_ENVIRONMENT_ALLOWLIST
    }
    env.setdefault("HOME", str(Path.home()))
    env.setdefault("PATH", "/usr/local/bin:/usr/bin:/bin")
    env.setdefault("DISPLAY", ":0")
    env.update(
        {
            "SECUREWAVE_RUNTIME_PROBE_EMAIL": email,
            "SECUREWAVE_RUNTIME_PROBE_PASSWORD": password,
            "SECUREWAVE_RUNTIME_PROBE_AUTH_MODE": auth_mode,
            "SECUREWAVE_RUNTIME_PROBE_PROTOCOL": protocol,
            "SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS": str(hold_seconds),
            "SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER": "true",
            "SECUREWAVE_RUNTIME_PROBE_RESET_REFERENCES": "true",
            "SECUREWAVE_RUNTIME_PROBE_ALLOW_UNADVERTISED_OPENVPN": (
                "true" if protocol == "openvpn" else "false"
            ),
            "SECUREWAVE_USE_MOCK_API": use_mock_api,
        }
    )
    if api_base:
        env["SECUREWAVE_API_BASE_URL"] = api_base
    else:
        env.pop("SECUREWAVE_API_BASE_URL", None)
    if server_id:
        env["SECUREWAVE_RUNTIME_PROBE_SERVER_ID"] = server_id
    else:
        env.pop("SECUREWAVE_RUNTIME_PROBE_SERVER_ID", None)
    return env


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


def _attempt(
    argv: list[str],
    result: CommandResult,
    *,
    redact_stdout: bool = False,
) -> dict[str, object]:
    result_payload = result.as_dict()
    if redact_stdout and result_payload["stdout"]:
        result_payload["stdout"] = "[redacted]"
    return {
        "command": argv,
        "result": result_payload,
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


def _helper_response_ok(response: dict[str, str]) -> bool:
    try:
        contract = int(response.get("contract", ""))
    except (TypeError, ValueError):
        return False
    return response.get("ok") == "true" and contract >= MINIMUM_HELPER_CONTRACT


def _helper_evidence(
    fields: dict[str, str], timeout: float = 20.0
) -> dict[str, object]:
    try:
        response = _helper_request(fields, timeout=timeout)
    except OSError as exc:
        return {
            "ok": False,
            "error": str(exc),
            "response": {"ok": "false", "code": "socket_error", "message": str(exc)},
        }
    ok = _helper_response_ok(response)
    result: dict[str, object] = {"ok": ok, "response": response}
    if response.get("ok") == "true" and not ok:
        result["error"] = (
            "helper response contract is missing, invalid, or older than "
            f"{MINIMUM_HELPER_CONTRACT}"
        )
    return result


def _helper_evidence_with_budget(
    fields: dict[str, str],
    *,
    timeout: float,
    deadline: float | None,
) -> dict[str, object]:
    bounded_timeout = _remaining_timeout(deadline, timeout)
    if bounded_timeout <= 0:
        return {"ok": False, "error": "evidence timeout exhausted", "response": {}}
    return _helper_evidence(fields, timeout=bounded_timeout)


def _state_path(filename: str) -> str:
    return str(Path.home() / ".config" / "securewave" / filename)


def _cleanup_protocol_residue(protocol: str) -> list[dict[str, object]]:
    requests: list[dict[str, str]] = []
    if protocol == "wireguard":
        requests.append(
            {"op": "wireguard.cleanup", "config_path": _state_path("sw-wg.conf")}
        )
    elif protocol == "openvpn":
        config_path = _state_path("securewave.ovpn")
        # Contract 13 deliberately rejects cleanup requests whose config file
        # does not exist. A fresh install has nothing for the helper to stop;
        # the residue verifier below still fails closed on any surviving
        # OpenVPN process, interface, route, or DNS state.
        if not Path(config_path).is_file():
            return [
                {
                    "protocol": protocol,
                    "request": None,
                    "response": {
                        "ok": "true",
                        "contract": str(MINIMUM_HELPER_CONTRACT),
                        "status": "disconnected",
                        "message": "No OpenVPN runtime config exists; cleanup is unnecessary.",
                    },
                    "ok": True,
                    "skipped": True,
                }
            ]
        requests.append(
            {
                "op": "openvpn.cleanup",
                "config_path": config_path,
                "pid_path": _state_path("securewave-openvpn.pid"),
                "log_path": _state_path("securewave-openvpn.log"),
                "auth_path": _state_path("securewave-openvpn.auth"),
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
        actions.append(
            {
                "protocol": protocol,
                "request": request,
                "response": response,
                "ok": _helper_response_ok(response),
            }
        )
    return actions


def _health_url(api_base: str | None) -> str:
    return (api_base or "").rstrip("/") + "/health"


def _backend_health_evidence(
    api_base: str | None, *, timeout: float = 15.0
) -> dict[str, object]:
    if not api_base:
        return {
            "ok": False,
            "error_kind": "api_base_required",
            "error": "an explicit local or staging API base is required",
        }
    url = _health_url(api_base)
    if timeout <= 0:
        return {
            "ok": False,
            "url": url,
            "elapsed_ms": 0,
            "error": "evidence timeout exhausted",
        }
    request = urllib.request.Request(
        url, headers={"User-Agent": "SecureWaveLinuxProof/1"}
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    started_at = time.monotonic()
    try:
        with opener.open(request, timeout=timeout) as response:  # nosec B310
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
            "--noproxy",
            "*",
            "-m",
            "5",
            "-sS",
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


def _dns_interface_evidence(
    protocol: str,
    *,
    deadline: float | None,
) -> dict[str, object]:
    if protocol == "wireguard":
        return {"ok": True, "interface": WIREGUARD_INTERFACE}
    if protocol == "openvpn":
        log = _openvpn_log_evidence()
        interface = log.get("interface")
        return {
            "ok": bool(log.get("ok")) and isinstance(interface, str),
            "interface": interface,
            "log": log,
        }
    if protocol == "ikev2":
        status = _helper_evidence_with_budget(
            {"op": "ikev2.status"}, timeout=10, deadline=deadline
        )
        response = status.get("response")
        interface = (
            IKEV2_INTERFACE
            if isinstance(response, dict)
            and response.get("status") == "connected"
            and response.get("interface") == IKEV2_INTERFACE
            and response.get("interface_present") == "true"
            and response.get("xfrm_interface") == "true"
            else None
        )
        return {
            "ok": bool(status.get("ok")) and interface is not None,
            "interface": interface,
            "helper_status": status,
        }
    raise ValueError(f"unsupported protocol: {protocol}")


def _helper_counter_snapshot(
    protocol: str,
    *,
    deadline: float | None,
) -> dict[str, object]:
    if protocol == "wireguard":
        counters = _wireguard_counter_evidence(deadline=deadline)
        return {
            **counters,
            "ok": counters.get("available") is True,
        }
    if protocol == "openvpn":
        request = {
            "op": "openvpn.status",
            "config_path": _state_path("securewave.ovpn"),
            "pid_path": _state_path("securewave-openvpn.pid"),
            "log_path": _state_path("securewave-openvpn.log"),
        }
    elif protocol == "ikev2":
        request = {"op": "ikev2.status"}
    else:
        raise ValueError(f"unsupported protocol: {protocol}")
    result = _helper_evidence_with_budget(request, timeout=10, deadline=deadline)
    response = result.get("response")
    try:
        rx_bytes = int(response.get("rx_bytes", "")) if isinstance(response, dict) else -1
        tx_bytes = int(response.get("tx_bytes", "")) if isinstance(response, dict) else -1
    except (TypeError, ValueError):
        rx_bytes = -1
        tx_bytes = -1
    owned_ikev2 = (
        protocol != "ikev2"
        or (
            isinstance(response, dict)
            and response.get("interface") == IKEV2_INTERFACE
            and response.get("ownership_inspection_ok") == "true"
            and response.get("xfrm_pair_present") == "true"
            and response.get("endpoint_bypass_inspection_ok") == "true"
            and response.get("endpoint_bypass_present") == "true"
        )
    )
    available = (
        bool(result.get("ok"))
        and isinstance(response, dict)
        and response.get("status") == "connected"
        and response.get("counters_available") == "true"
        and rx_bytes >= 0
        and tx_bytes >= 0
        and owned_ikev2
    )
    return {
        "ok": available,
        "rx_bytes": max(rx_bytes, 0),
        "tx_bytes": max(tx_bytes, 0),
        "helper": {
            key: response[key]
            for key in ("contract", "status", "interface")
            if isinstance(response, dict) and key in response
        },
    }


def _resolvectl_dns_server_count(output: str) -> int:
    _, separator, values = output.partition(":")
    if not separator:
        return 0
    count = 0
    for token in values.split():
        try:
            ipaddress.ip_address(token.split("%", 1)[0])
        except ValueError:
            continue
        count += 1
    return count


def _dns_evidence(
    protocol: str,
    deadline: float | None = None,
) -> dict[str, object]:
    interface_evidence = _dns_interface_evidence(protocol, deadline=deadline)
    interface = interface_evidence.get("interface")
    if not interface_evidence.get("ok") or not isinstance(interface, str):
        return {
            "ok": False,
            "error_kind": "dns_tunnel_interface_unavailable",
            "interface_evidence": interface_evidence,
        }

    dns_command = ["resolvectl", "dns", interface]
    dns_result = _run_with_budget(dns_command, timeout=5, deadline=deadline)
    domain_command = ["resolvectl", "domain", interface]
    domain_result = _run_with_budget(domain_command, timeout=5, deadline=deadline)
    server_count = _resolvectl_dns_server_count(dns_result.stdout)
    route_all_domains = "~." in domain_result.stdout.split()
    resolver_config = {
        "ok": (
            dns_result.returncode == 0
            and server_count > 0
            and domain_result.returncode == 0
            and route_all_domains
        ),
        "interface": interface,
        "server_count": server_count,
        "route_all_domains": route_all_domains,
        "dns": _attempt(dns_command, dns_result, redact_stdout=True),
        "domains": _attempt(domain_command, domain_result, redact_stdout=True),
    }
    if not resolver_config["ok"]:
        return {
            "ok": False,
            "error_kind": "dns_resolver_not_owned_by_tunnel",
            "interface_evidence": interface_evidence,
            "resolver_config": resolver_config,
        }

    attempts: list[dict[str, object]] = []
    successful_hosts: dict[str, str] = {}
    for record_type in ("A", "AAAA"):
        for host in DNS_TEST_HOSTS:
            before = _helper_counter_snapshot(protocol, deadline=deadline)
            command = [
                "resolvectl",
                f"--interface={interface}",
                "--cache=no",
                "--network=yes",
                "--legend=no",
                f"--type={record_type}",
                "query",
                host,
            ]
            result = _run_with_budget(command, timeout=8, deadline=deadline)
            after = _helper_counter_snapshot(protocol, deadline=deadline)
            rx_delta = int(after.get("rx_bytes", 0)) - int(
                before.get("rx_bytes", 0)
            )
            tx_delta = int(after.get("tx_bytes", 0)) - int(
                before.get("tx_bytes", 0)
            )
            owned_response = f"-- link: {interface}" in result.stdout
            attempt = {
                **_attempt(command, result),
                "record_type": record_type,
                "counter_before": before,
                "counter_after": after,
                "rx_delta": rx_delta,
                "tx_delta": tx_delta,
                "owned_response": owned_response,
            }
            attempts.append(attempt)
            if (
                before.get("ok") is True
                and after.get("ok") is True
                and result.returncode == 0
                and owned_response
                and rx_delta > 0
                and tx_delta > 0
            ):
                successful_hosts[record_type] = host
                break
        if record_type not in successful_hosts:
            break
    if set(successful_hosts) == {"A", "AAAA"}:
        return {
            "ok": True,
            "hostname": successful_hosts["A"],
            "record_types": successful_hosts,
            "interface": interface,
            "resolver_config": resolver_config,
            "attempts": attempts,
        }
    return {
        "ok": False,
        "error_kind": "dns_broken_or_outside_tunnel",
        "interface_evidence": interface_evidence,
        "resolver_config": resolver_config,
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


def _extract_ipv6(value: str) -> str | None:
    for raw in value.replace(",", " ").split():
        token = raw.strip()
        try:
            address = ipaddress.ip_address(token)
        except ValueError:
            continue
        if address.version == 6:
            return str(address)
    return None


def _exit_ip_lookup(deadline: float | None = None) -> dict[str, object]:
    attempts: list[dict[str, object]] = []
    for url in EXIT_IP_URLS:
        command = [
            "curl",
            "-4",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
            url,
        ]
        result = _run_with_budget(command, timeout=9, deadline=deadline)
        attempts.append(_attempt(command, result, redact_stdout=True))
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


def _ipv6_exit_ip_lookup(deadline: float | None = None) -> dict[str, object]:
    attempts: list[dict[str, object]] = []
    for url in IPV6_EXIT_IP_URLS:
        command = [
            "curl",
            "-6",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
            url,
        ]
        result = _run_with_budget(command, timeout=9, deadline=deadline)
        attempts.append(_attempt(command, result, redact_stdout=True))
        ip = _extract_ipv6(result.stdout)
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
        "error_kind": "ipv6_exit_ip_unavailable",
        "attempts": attempts,
    }


def _public_exit_ip_lookup(evidence: dict[str, object]) -> dict[str, object]:
    literal_ip = evidence.get("ip")
    public_attempts: list[object] = []
    attempts = evidence.get("attempts", [])
    if isinstance(attempts, list):
        for attempt in attempts:
            if not isinstance(attempt, dict):
                public_attempts.append(attempt)
                continue
            public_attempt = dict(attempt)
            result = public_attempt.get("result")
            if isinstance(result, dict):
                public_result = dict(result)
                public_result.pop("stdout", None)
                if isinstance(literal_ip, str):
                    for key, value in public_result.items():
                        if isinstance(value, str):
                            public_result[key] = value.replace(
                                literal_ip, "[redacted-exit-ip]"
                            )
                public_attempt["result"] = public_result
            public_attempts.append(public_attempt)
    public = {
        "ok": evidence.get("ok") is True,
        "observed": bool(evidence.get("ip")),
        "attempts": public_attempts,
    }
    if evidence.get("url"):
        public["url"] = evidence["url"]
    if evidence.get("error_kind"):
        public["error_kind"] = evidence["error_kind"]
    return public


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
    pre_connect_observed = bool(pre_connect.get("ip"))
    connected_observed = bool(connected.get("ip"))
    evidence: dict[str, object] = {
        "ok": False,
        "pre_connect_observed": pre_connect_observed,
        "connected_observed": connected_observed,
        "changed": False,
    }
    if not pre_connect.get("ok") or not connected.get("ok"):
        evidence["error_kind"] = "exit_ip_unavailable"
        return evidence
    if pre_connect.get("ip") == connected.get("ip"):
        evidence["error_kind"] = "exit_ip_unchanged"
        return evidence
    evidence["ok"] = True
    evidence["changed"] = True
    return evidence


def _ipv6_block_status(
    protocol: str,
    *,
    deadline: float | None,
) -> dict[str, object]:
    if protocol == "wireguard":
        request = {"op": "wireguard.status"}
        required = {
            "status": "connected",
            "interface": WIREGUARD_INTERFACE,
            "ipv6_mode": "block",
            "ipv6_route_via_sw_wg": "true",
            "firewall_inspection_ok": "true",
            "ipv6_block_present": "true",
            "handshake_inspection_ok": "true",
            "handshake_present": "true",
            "endpoint_inspection_ok": "true",
            "endpoint_bypass_present": "true",
        }
    elif protocol == "openvpn":
        request = {
            "op": "openvpn.status",
            "config_path": _state_path("securewave.ovpn"),
            "pid_path": _state_path("securewave-openvpn.pid"),
            "log_path": _state_path("securewave-openvpn.log"),
        }
        required = {
            "status": "connected",
            "interface": OPENVPN_INTERFACE,
            "ipv6_mode": "block",
            "ipv6_route_present": "true",
            "ipv6_block_configured": "true",
        }
    elif protocol == "ikev2":
        request = {"op": "ikev2.status"}
        required = {
            "status": "connected",
            "interface": IKEV2_INTERFACE,
            "ipv6_mode": "block",
            "ipv6_block_inspection_ok": "true",
            "ipv6_block_present": "true",
            "ownership_inspection_ok": "true",
        }
    else:
        raise ValueError(f"unsupported protocol: {protocol}")
    helper = _helper_evidence_with_budget(request, timeout=10, deadline=deadline)
    response = helper.get("response")
    matched = bool(helper.get("ok")) and isinstance(response, dict) and all(
        response.get(key) == value for key, value in required.items()
    )
    return {
        "ok": matched,
        "mode": "block",
        "required": required,
        "observed": {
            key: response.get(key)
            for key in required
            if isinstance(response, dict) and key in response
        },
    }


def _ipv6_protection_evidence(
    protocol: str,
    pre_connect_ipv6_exit_ip: dict[str, object] | None,
    *,
    deadline: float | None = None,
) -> dict[str, object]:
    baseline = pre_connect_ipv6_exit_ip or {
        "ok": False,
        "ip": None,
        "error_kind": "ipv6_baseline_unavailable",
        "attempts": [],
    }
    block = _ipv6_block_status(protocol, deadline=deadline)
    connected = _ipv6_exit_ip_lookup(deadline=deadline)
    evidence: dict[str, object] = {
        "ok": False,
        "mode": "block",
        "pre_connect_observed": bool(baseline.get("ip")),
        "connected_observed": bool(connected.get("ip")),
        "block": block,
        "connected_probe": _public_exit_ip_lookup(connected),
    }
    if baseline.get("ok") is not True or not baseline.get("ip"):
        evidence["error_kind"] = "ipv6_baseline_unavailable"
        return evidence
    if block.get("ok") is not True:
        evidence["error_kind"] = "ipv6_block_not_owned"
        return evidence
    if connected.get("ok") is True or connected.get("ip"):
        evidence["error_kind"] = "ipv6_not_blocked"
        return evidence
    evidence["ok"] = True
    return evidence


def _ipv6_recovery_evidence(
    pre_connect_ipv6_exit_ip: dict[str, object] | None,
    *,
    deadline: float | None = None,
) -> dict[str, object]:
    baseline_observed = bool(
        pre_connect_ipv6_exit_ip
        and pre_connect_ipv6_exit_ip.get("ok") is True
        and pre_connect_ipv6_exit_ip.get("ip")
    )
    recovered = _ipv6_exit_ip_lookup(deadline=deadline)
    return {
        "ok": baseline_observed and recovered.get("ok") is True,
        "baseline_observed": baseline_observed,
        "recovered": _public_exit_ip_lookup(recovered),
        "error_kind": (
            None
            if baseline_observed and recovered.get("ok") is True
            else "ipv6_not_restored_after_disconnect"
        ),
    }


def _ikev2_routing_rule_evidence(deadline: float | None = None) -> dict[str, object]:
    bad_rules: list[str] = []
    safe_rule_counts: dict[str, int] = {}
    inspections: dict[str, object] = {}
    inspection_ok = True
    for label, family in (("ipv4", "-4"), ("ipv6", "-6")):
        command = ["ip", family, "-N", "rule", "show"]
        result = _run_with_budget(command, timeout=5, deadline=deadline)
        inspections[label] = _attempt(command, result)
        inspection_ok = inspection_ok and result.returncode == 0
        safe_count = 0
        bad_count_before_family = len(bad_rules)
        for raw_line in result.stdout.splitlines():
            line = " ".join(raw_line.split())
            if re.fullmatch(r"220: from all (?:lookup|table) 220", line):
                bad_rules.append(f"{label}: unqualified pref-220/table-220 rule")
                continue
            targets_ikev2_table = re.search(
                r"(?:^| )(?:lookup|table) 210(?: |$)", line
            ) is not None
            expected_safe_rule = re.fullmatch(
                r"210: (?:not from all|from all not) fwmark "
                r"0xdc(?:/0xffffffff)? (?:lookup|table) 210",
                line,
            )
            if targets_ikev2_table and expected_safe_rule is None:
                bad_rules.append(f"{label}: {raw_line.strip()}")
            elif targets_ikev2_table:
                safe_count += 1
        safe_rule_counts[label] = safe_count
        if (
            result.returncode == 0
            and safe_count != 1
            and len(bad_rules) == bad_count_before_family
        ):
            bad_rules.append(
                f"{label}: expected one safe table-210 rule, found {safe_count}"
            )
    return {
        "ok": inspection_ok and not bad_rules,
        "error_kind": (
            "ikev2_routing_loop_rule"
            if bad_rules
            else (None if inspection_ok else "ikev2_routing_rule_inspection_failed")
        ),
        "bad_rules": bad_rules,
        "safe_rule_counts": safe_rule_counts,
        "ip_rules": inspections,
    }


def _wireguard_counter_evidence(
    deadline: float | None = None,
) -> dict[str, object]:
    result = _helper_evidence_with_budget(
        {"op": "wireguard.counters"},
        timeout=10,
        deadline=deadline,
    )
    response = result.get("response")
    stdout = response.get("stdout", "") if isinstance(response, dict) else ""
    source_rows = [line for line in stdout.splitlines() if line.strip()]
    rows = []
    for line in source_rows:
        fields = line.split()
        if len(fields) != 3:
            continue
        try:
            rx_bytes = int(fields[1])
            tx_bytes = int(fields[2])
        except ValueError:
            continue
        if rx_bytes < 0 or tx_bytes < 0:
            continue
        rows.append((rx_bytes, tx_bytes))
    rx_bytes = sum(row[0] for row in rows)
    tx_bytes = sum(row[1] for row in rows)
    helper_summary = {
        key: response[key]
        for key in ("contract", "code")
        if isinstance(response, dict) and key in response
    }
    available = (
        bool(result.get("ok"))
        and bool(rows)
        and len(rows) == len(source_rows)
    )
    return {
        "ok": available and rx_bytes > 0 and tx_bytes > 0,
        "available": available,
        "peer_rows": len(rows),
        "rx_bytes": rx_bytes,
        "tx_bytes": tx_bytes,
        "total_bytes": rx_bytes + tx_bytes,
        "helper": helper_summary,
    }


def _positive_helper_counters(response: object) -> bool:
    if not isinstance(response, dict) or response.get("counters_available") != "true":
        return False
    try:
        rx_bytes = int(response.get("rx_bytes", ""))
        tx_bytes = int(response.get("tx_bytes", ""))
    except (TypeError, ValueError):
        return False
    return rx_bytes > 0 and tx_bytes > 0


def _tun_interface_evidence(deadline: float | None = None) -> dict[str, object]:
    links = _run_with_budget(["ip", "-o", "link", "show"], timeout=5, deadline=deadline)
    interfaces: list[str] = []
    if links.returncode == 0:
        for line in links.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) < 2:
                continue
            name = parts[1].strip().split("@", 1)[0]
            if name == OPENVPN_INTERFACE:
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
    interface = None
    for line in lines:
        match = re.search(
            rf"\bTUN/TAP device ({re.escape(OPENVPN_INTERFACE)}) opened\b", line
        )
        if match:
            interface = match.group(1)
    return {
        "ok": success and interface is not None,
        "path": str(path),
        "interface": interface,
        "tail": [line.strip() for line in lines[-12:] if line.strip()],
    }


def _nmcli_has_value(output: str, prefixes: tuple[str, ...]) -> bool:
    for raw_line in output.splitlines():
        key, separator, value = raw_line.partition(":")
        if separator and key.startswith(prefixes) and value.strip() not in ("", "--"):
            return True
    return False


def _runtime_evidence_for(
    protocol: str,
    api_base: str | None,
    deadline: float | None = None,
) -> dict[str, object]:
    if protocol == "wireguard":
        link = _run_with_budget(
            ["ip", "link", "show", WIREGUARD_INTERFACE],
            timeout=5,
            deadline=deadline,
        )
        route4 = _run_with_budget(
            ["ip", "-4", "route", "get", "1.1.1.1"],
            timeout=5,
            deadline=deadline,
        )
        route6 = _run_with_budget(
            ["ip", "-6", "route", "get", "2606:4700:4700::1111"],
            timeout=5,
            deadline=deadline,
        )
        route_ok = all(
            route.returncode == 0
            and f" dev {WIREGUARD_INTERFACE}" in route.stdout
            for route in (route4, route6)
        )
        helper_status = _helper_evidence_with_budget(
            {"op": "wireguard.status"}, timeout=10, deadline=deadline
        )
        helper_response = helper_status.get("response")
        helper_ok = (
            bool(helper_status.get("ok"))
            and isinstance(helper_response, dict)
            and helper_response.get("status") == "connected"
            and helper_response.get("interface") == WIREGUARD_INTERFACE
            and helper_response.get("route_via_sw_wg") == "true"
            and helper_response.get("ipv4_route_via_sw_wg") == "true"
            and helper_response.get("ipv6_route_via_sw_wg") == "true"
            and helper_response.get("policy_rules_present") == "true"
            and helper_response.get("policy_routes_present") == "true"
            and helper_response.get("firewall_inspection_ok") == "true"
            and helper_response.get("ipv4_kill_switch_present") == "true"
            and helper_response.get("ipv6_block_present") == "true"
            and helper_response.get("ipv6_mode") == "block"
            and helper_response.get("handshake_inspection_ok") == "true"
            and helper_response.get("handshake_present") == "true"
            and helper_response.get("endpoint_inspection_ok") == "true"
            and helper_response.get("endpoint_bypass_present") == "true"
        )
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        counters = _wireguard_counter_evidence(deadline=deadline)
        return {
            "ok": link.returncode == 0
            and route_ok
            and helper_ok
            and bool(backend_health.get("ok"))
            and bool(counters.get("ok")),
            "interface": link.as_dict(),
            "routes": {"ipv4": route4.as_dict(), "ipv6": route6.as_dict()},
            "helper_status": helper_status,
            "backend_health": backend_health,
            "traffic_counters": counters,
        }
    if protocol == "openvpn":
        tun = _tun_interface_evidence(deadline=deadline)
        route4 = _run_with_budget(
            ["ip", "-4", "route", "get", "1.1.1.1"],
            timeout=5,
            deadline=deadline,
        )
        route6 = _run_with_budget(
            ["ip", "-6", "route", "get", "2606:4700:4700::1111"],
            timeout=5,
            deadline=deadline,
        )
        log = _openvpn_log_evidence()
        helper_status = _helper_evidence_with_budget(
            {
                "op": "openvpn.status",
                "config_path": _state_path("securewave.ovpn"),
                "pid_path": _state_path("securewave-openvpn.pid"),
                "log_path": _state_path("securewave-openvpn.log"),
            },
            timeout=10,
            deadline=deadline,
        )
        helper_response = helper_status.get("response")
        log_interface = log.get("interface")
        tun_interfaces = tun.get("interfaces")
        owned_interface_ok = (
            isinstance(log_interface, str)
            and isinstance(tun_interfaces, list)
            and log_interface in tun_interfaces
            and all(
                route.returncode == 0 and f" dev {log_interface}" in route.stdout
                for route in (route4, route6)
            )
            and isinstance(helper_response, dict)
            and helper_response.get("interface") == log_interface
        )
        helper_ok = (
            bool(helper_status.get("ok"))
            and isinstance(helper_response, dict)
            and helper_response.get("status") == "connected"
            and helper_response.get("process_present") == "true"
            and helper_response.get("initialization_complete") == "true"
            and helper_response.get("interface_present") == "true"
            and helper_response.get("route_present") == "true"
            and helper_response.get("ipv4_route_present") == "true"
            and helper_response.get("ipv6_route_present") == "true"
            and helper_response.get("ipv6_block_configured") == "true"
            and helper_response.get("ipv6_mode") == "block"
            and helper_response.get("dns_configured") == "true"
            and helper_response.get("interface") == OPENVPN_INTERFACE
            and _positive_helper_counters(helper_response)
        )
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        return {
            "ok": bool(tun.get("ok"))
            and owned_interface_ok
            and helper_ok
            and bool(log.get("ok"))
            and bool(backend_health.get("ok")),
            "interface": tun,
            "routes": {"ipv4": route4.as_dict(), "ipv6": route6.as_dict()},
            "helper_status": helper_status,
            "log": log,
            "backend_health": backend_health,
        }
    if protocol == "ikev2":
        active = _run_with_budget(
            ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"],
            timeout=8,
            deadline=deadline,
        )
        dns = _run_with_budget(
            [
                "nmcli",
                "-t",
                "-f",
                "IP4.DNS,IP6.DNS",
                "connection",
                "show",
                IKEV2_CONNECTION,
            ],
            timeout=8,
            deadline=deadline,
        )
        helper_status = _helper_evidence_with_budget(
            {"op": "ikev2.status"},
            timeout=10,
            deadline=deadline,
        )
        helper_response = helper_status.get("response")
        backend_health = _backend_health_evidence(
            api_base,
            timeout=_remaining_timeout(deadline, 15),
        )
        active_ok = (
            active.returncode == 0
            and f"{IKEV2_CONNECTION}:vpn" in active.stdout.splitlines()
        )
        dns_ok = dns.returncode == 0 and _nmcli_has_value(
            dns.stdout,
            ("IP4.DNS", "IP6.DNS"),
        )
        owned_runtime_ok = (
            bool(helper_status.get("ok"))
            and isinstance(helper_response, dict)
            and helper_response.get("status") == "connected"
            and helper_response.get("connection_inspection_ok") == "true"
            and helper_response.get("connection_present") == "true"
            and helper_response.get("nm_active") == "true"
            and helper_response.get("interface_name_configured") == "true"
            and helper_response.get("interface_inspection_ok") == "true"
            and helper_response.get("interface_present") == "true"
            and helper_response.get("interface") == IKEV2_INTERFACE
            and helper_response.get("xfrm_interface") == "true"
            and helper_response.get("xfrm_if_id_present") == "true"
            and helper_response.get("xfrm_if_id_persisted") == "true"
            and helper_response.get("ownership_inspection_ok") == "true"
            and helper_response.get("route_inspection_ok") == "true"
            and helper_response.get("route_present") == "true"
            and helper_response.get("ipv4_full_route_present") == "true"
            and helper_response.get("ipv6_mode") == "block"
            and helper_response.get("ipv6_block_inspection_ok") == "true"
            and helper_response.get("ipv6_block_present") == "true"
            and helper_response.get("route_conflict_present") == "false"
            and helper_response.get("dns_present") == "true"
            and helper_response.get("xfrm_state_inspection_ok") == "true"
            and helper_response.get("xfrm_state_present") == "true"
            and helper_response.get("xfrm_esp_present") == "true"
            and helper_response.get("xfrm_policy_inspection_ok") == "true"
            and helper_response.get("xfrm_policy_present") == "true"
            and helper_response.get("xfrm_pair_present") == "true"
            and helper_response.get("endpoint_bypass_inspection_ok") == "true"
            and helper_response.get("endpoint_bypass_present") == "true"
            and helper_response.get("routing_rule_inspection_ok") == "true"
            and helper_response.get("routing_rules_safe") == "true"
            and helper_response.get("routing_loop_rule_present") == "false"
            and helper_response.get("legacy_routing_loop_rule_present") == "false"
            and _positive_helper_counters(helper_response)
        )
        return {
            "ok": active_ok
            and dns_ok
            and owned_runtime_ok
            and bool(backend_health.get("ok")),
            "active_connection": active.as_dict(),
            "dns": dns.as_dict(),
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
    ipv6_protection: dict[str, object] | None = None,
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
    if ipv6_protection is not None:
        evidence["ipv6_protection"] = ipv6_protection
    if ikev2_routing_rule is not None:
        evidence["ikev2_routing_rule"] = ikev2_routing_rule
    return evidence


def _evidence_for(
    protocol: str,
    api_base: str | None,
    *,
    pre_connect_exit_ip: dict[str, object] | None = None,
    pre_connect_ipv6_exit_ip: dict[str, object] | None = None,
    evidence_deadline: float | None = None,
) -> dict[str, object]:
    data_plane = _data_plane_evidence(deadline=evidence_deadline)
    if not data_plane.get("ok"):
        return _failed_network_evidence(
            error_kind="data_plane_unreachable",
            data_plane=data_plane,
        )

    dns = _dns_evidence(protocol, deadline=evidence_deadline)
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

    ipv6_protection = _ipv6_protection_evidence(
        protocol,
        pre_connect_ipv6_exit_ip,
        deadline=evidence_deadline,
    )
    if not ipv6_protection.get("ok"):
        return _failed_network_evidence(
            error_kind=str(
                ipv6_protection.get("error_kind") or "ipv6_protection_failed"
            ),
            data_plane=data_plane,
            dns=dns,
            exit_ip=exit_ip,
            ipv6_protection=ipv6_protection,
        )

    ikev2_routing_rule = None
    if protocol == "ikev2":
        ikev2_routing_rule = _ikev2_routing_rule_evidence(deadline=evidence_deadline)
        if not ikev2_routing_rule.get("ok"):
            return _failed_network_evidence(
                error_kind=str(
                    ikev2_routing_rule.get("error_kind")
                    or "ikev2_routing_rule_inspection_failed"
                ),
                data_plane=data_plane,
                dns=dns,
                exit_ip=exit_ip,
                ipv6_protection=ipv6_protection,
                ikev2_routing_rule=ikev2_routing_rule,
            )

    runtime = _runtime_evidence_for(protocol, api_base, deadline=evidence_deadline)
    runtime.update(
        {
            "data_plane": data_plane,
            "dns": dns,
            "exit_ip": exit_ip,
            "ipv6_protection": ipv6_protection,
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


def _probe_event_evidence(
    probe_events: list[dict[str, object]],
    protocol: str,
    expected_hold_seconds: int,
) -> dict[str, object]:
    expected_names = (
        "connect_result",
        "holding_for_evidence",
        "disconnect_result",
    )
    matching = {
        name: [
            (index, event)
            for index, event in enumerate(probe_events)
            if event.get("event") == name
        ]
        for name in expected_names
    }
    errors: list[str] = []
    for name in expected_names:
        count = len(matching[name])
        if count != 1:
            errors.append(f"expected exactly one {name} event, observed {count}")

    if errors:
        return {"ok": False, "errors": errors, "events": matching}

    connect_index, connect = matching["connect_result"][0]
    hold_index, hold = matching["holding_for_evidence"][0]
    disconnect_index, disconnect = matching["disconnect_result"][0]
    if connect.get("status") != "connected":
        errors.append("connect_result did not report connected")
    if connect.get("protocol") != protocol:
        errors.append("connect_result did not report the requested protocol")
    if connect.get("last_profile_fetch_ok") is not True:
        errors.append("connect_result did not prove a successful profile fetch")
    if connect.get("last_tunnel_start_ok") is not True:
        errors.append("connect_result did not prove a successful tunnel start")
    if hold.get("protocol") != protocol:
        errors.append("holding_for_evidence did not report the requested protocol")
    hold_seconds = hold.get("hold_seconds")
    if type(hold_seconds) is not int or hold_seconds != expected_hold_seconds:
        errors.append("holding_for_evidence did not report the requested hold duration")
    if disconnect.get("status") != "disconnected":
        errors.append("disconnect_result did not report disconnected")
    if disconnect.get("protocol") != protocol:
        errors.append("disconnect_result did not report the requested protocol")
    if not connect_index < hold_index < disconnect_index:
        errors.append(
            "probe events were not emitted in connect, hold, disconnect order"
        )
    hold_elapsed_ms = hold.get("probe_elapsed_ms")
    disconnect_elapsed_ms = disconnect.get("probe_elapsed_ms")
    if type(hold_elapsed_ms) is not int or hold_elapsed_ms < 0:
        errors.append("holding_for_evidence did not report a valid elapsed time")
    if type(disconnect_elapsed_ms) is not int or disconnect_elapsed_ms < 0:
        errors.append("disconnect_result did not report a valid elapsed time")
    if (
        type(hold_elapsed_ms) is int
        and type(disconnect_elapsed_ms) is int
        and disconnect_elapsed_ms - hold_elapsed_ms < expected_hold_seconds * 1000
    ):
        errors.append("disconnect_result occurred before the requested hold elapsed")
    return {
        "ok": not errors,
        "errors": errors,
        "connect_result": connect,
        "holding_for_evidence": hold,
        "disconnect_result": disconnect,
    }


def _late_hold_evidence_window(
    hold_observed_at: float,
    hold_seconds: int,
) -> tuple[float, float]:
    hold_duration = float(hold_seconds)
    lead = min(LATE_HOLD_EVIDENCE_MAX_LEAD_SECONDS, hold_duration / 2.0)
    finish_margin = min(1.0, hold_duration / 10.0)
    return (
        hold_observed_at + hold_duration - lead,
        hold_observed_at + hold_duration - finish_margin,
    )


def _is_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    return value.strip().lower() in PLACEHOLDER_VALUES


def _credential_error(email: str | None, password: str | None) -> str | None:
    if email is None or not email.strip() or password is None or not password.strip():
        return (
            "existing live account credentials are required via "
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


def _stop_process_group(
    process: subprocess.Popen[bytes], *, force: bool = False
) -> None:
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


def _record_probe_output_line(
    line: str,
    output: list[str],
    probe_events: list[dict[str, object]],
    *,
    email: str,
    password: str,
) -> dict[str, object] | None:
    raw_line = line.rstrip()
    raw_event = _json_line(raw_line)
    redacted_line = _redact_sensitive_text(
        raw_line, email=email, password=password
    )
    output.append(redacted_line)
    if raw_event is None:
        return None
    event = _redact_sensitive_value(raw_event, email=email, password=password)
    if not isinstance(event, dict):
        raise AssertionError("probe event redaction changed its object type")
    safe_enums = {
        "event": {
            "connect_result",
            "holding_for_evidence",
            "disconnect_result",
            "runtime_probe_error",
        },
        "status": {
            "connected",
            "connecting",
            "disconnected",
            "disconnecting",
            "error",
        },
        "protocol": set(SUPPORTED_PROTOCOLS),
    }
    for key, allowed_values in safe_enums.items():
        raw_value = raw_event.get(key)
        if isinstance(raw_value, str) and raw_value in allowed_values:
            event[key] = raw_value
    probe_events.append(event)
    return event


def _drain_available_stdout(
    process: subprocess.Popen[bytes],
    pending: bytes,
    output: list[str],
    probe_events: list[dict[str, object]],
    *,
    email: str,
    password: str,
) -> bytes:
    if process.stdout is None:
        return pending
    while True:
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            break
        pending, _ = _consume_probe_stdout(
            pending,
            chunk,
            output,
            probe_events,
            email=email,
            password=password,
        )
    pending, _ = _consume_probe_stdout(
        pending,
        b"",
        output,
        probe_events,
        email=email,
        password=password,
        flush=True,
    )
    return pending


def _consume_probe_stdout(
    pending: bytes,
    chunk: bytes,
    output: list[str],
    probe_events: list[dict[str, object]],
    *,
    email: str,
    password: str,
    flush: bool = False,
) -> tuple[bytes, list[dict[str, object]]]:
    combined = pending + chunk
    raw_lines = combined.split(b"\n")
    if flush:
        pending = b""
    else:
        pending = raw_lines.pop()
    events: list[dict[str, object]] = []
    for raw_line in raw_lines:
        if not raw_line:
            continue
        event = _record_probe_output_line(
            raw_line.decode("utf-8", errors="replace"),
            output,
            probe_events,
            email=email,
            password=password,
        )
        if event is not None:
            events.append(event)
    return pending, events


def run_protocol(
    *,
    probe_binary: Path,
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
    command = _build_probe_command(probe_binary)
    env = _build_probe_environment(
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
    pre_connect_ipv6_exit_ip = _ipv6_exit_ip_lookup(
        deadline=time.monotonic() + 20
    )

    started_at = time.monotonic()
    evidence_deadline = started_at + evidence_timeout
    process = subprocess.Popen(  # nosec B603
        command,
        cwd=probe_binary.parent,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
        start_new_session=True,
    )

    output: list[str] = []
    probe_events: list[dict[str, object]] = []
    evidence: dict[str, object] | None = None
    late_hold_evidence: dict[str, object] | None = None
    late_hold_evidence_due_at: float | None = None
    late_hold_evidence_deadline: float | None = None
    loop_error: str | None = None
    pending_stdout = b""

    if process.stdout is None:
        process.kill()
        raise RuntimeError("Flutter process stdout pipe was not created.")
    try:
        terminate_requested = False
        while True:
            ready, _, _ = select.select([process.stdout], [], [], 0.25)
            if ready:
                chunk = os.read(process.stdout.fileno(), 65536)
                if chunk:
                    pending_stdout, events = _consume_probe_stdout(
                        pending_stdout,
                        chunk,
                        output,
                        probe_events,
                        email=email,
                        password=password,
                    )
                    for event in events:
                        if event.get("event") == "holding_for_evidence":
                            if late_hold_evidence_due_at is None:
                                (
                                    late_hold_evidence_due_at,
                                    late_hold_evidence_deadline,
                                ) = _late_hold_evidence_window(
                                    time.monotonic(),
                                    hold_seconds,
                                )
                            if evidence is None:
                                evidence = _evidence_for(
                                    protocol,
                                    api_base,
                                    pre_connect_exit_ip=pre_connect_exit_ip,
                                    pre_connect_ipv6_exit_ip=pre_connect_ipv6_exit_ip,
                                    evidence_deadline=evidence_deadline,
                                )
                        elif event.get("event") == "runtime_probe_error":
                            evidence = _probe_error_evidence(event)
                            _stop_process_group(process)
                            terminate_requested = True
                            break
                else:
                    break
            if (
                not terminate_requested
                and late_hold_evidence is None
                and late_hold_evidence_due_at is not None
                and late_hold_evidence_deadline is not None
                and time.monotonic() >= late_hold_evidence_due_at
            ):
                late_hold_evidence = _evidence_for(
                    protocol,
                    api_base,
                    pre_connect_exit_ip=pre_connect_exit_ip,
                    pre_connect_ipv6_exit_ip=pre_connect_ipv6_exit_ip,
                    evidence_deadline=late_hold_evidence_deadline,
                )
            if terminate_requested:
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
            if time.monotonic() - started_at > evidence_timeout + hold_seconds + 15:
                loop_error = "runtime probe exceeded its total execution deadline"
                _stop_process_group(process)
                break
    except (Exception, KeyboardInterrupt) as exc:  # noqa: BLE001 - cleanup must run.
        loop_error = _redact_sensitive_text(
            f"{type(exc).__name__}: {exc}",
            email=email,
            password=password,
        )
        _stop_process_group(process)
    finally:
        try:
            returncode = process.wait(timeout=PROCESS_TERMINATION_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            _stop_process_group(process, force=True)
            returncode = process.wait(timeout=5)

    pending_stdout = _drain_available_stdout(
        process,
        pending_stdout,
        output,
        probe_events,
        email=email,
        password=password,
    )
    if pending_stdout:
        loop_error = loop_error or "runtime probe stdout ended with undecoded bytes"

    if evidence is None:
        evidence = {
            "ok": False,
            "error": loop_error or "probe exited before evidence window",
        }
    event_evidence = _probe_event_evidence(probe_events, protocol, hold_seconds)
    ipv6_recovery = _ipv6_recovery_evidence(
        pre_connect_ipv6_exit_ip,
        deadline=time.monotonic() + 20,
    )
    post_disconnect_verifier = _verifier()
    post_disconnect_checks = _json_object(post_disconnect_verifier.stdout)

    protocol_ok = (
        returncode == 0
        and loop_error is None
        and bool(evidence.get("ok"))
        and late_hold_evidence is not None
        and bool(late_hold_evidence.get("ok"))
        and bool(event_evidence.get("ok"))
        and bool(ipv6_recovery.get("ok"))
        and _verifier_succeeded(post_disconnect_verifier)
    )
    result = {
        "protocol": protocol,
        "ok": protocol_ok,
        "command": command,
        "returncode": returncode,
        "error": loop_error,
        "probe_events": probe_events,
        "event_evidence": event_evidence,
        "pre_connect_exit_ip": _public_exit_ip_lookup(pre_connect_exit_ip),
        "pre_connect_ipv6_exit_ip": _public_exit_ip_lookup(
            pre_connect_ipv6_exit_ip
        ),
        "evidence": evidence,
        "late_hold_evidence": late_hold_evidence,
        "post_disconnect_ipv6_recovery": ipv6_recovery,
        "post_disconnect_verifier_command": _verifier_command(),
        "post_disconnect_verifier": post_disconnect_verifier.as_dict(),
        "post_disconnect_checks": post_disconnect_checks,
    }
    if protocol_ok:
        result["output_tail"] = output[-80:]
    else:
        result["output"] = "\n".join(output)
    return result


def _positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a positive integer") from exc
    if value <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return value


def _disabled_mock_api(raw: str) -> str:
    if raw.strip().lower() in {"false", "0", "no"}:
        return "false"
    raise argparse.ArgumentTypeError(
        "must remain false; mock API runs cannot certify a VPN data plane"
    )


def _login_auth_mode(raw: str) -> str:
    if raw.strip().lower() == "login":
        return "login"
    raise argparse.ArgumentTypeError(
        "must remain login; certification requires a stable existing account"
    )


def _required_tools_evidence() -> dict[str, object]:
    resolved = {
        name: shutil.which(name)
        for name in ("flutter", "curl", "ip", "nmcli", "resolvectl")
    }
    missing = [name for name, path in resolved.items() if path is None]
    return {"ok": not missing, "resolved": resolved, "missing": missing}


def _verifier() -> CommandResult:
    return _run(_verifier_command(), timeout=30)


def _verifier_command() -> list[str]:
    return [sys.executable, "scripts/linux_vpn_runtime_verifier.py", "--json"]


def _verifier_succeeded(result: CommandResult) -> bool:
    body = _json_object(result.stdout)
    return result.returncode == 0 and body is not None and body.get("ok") is True


def _cleanup_actions_ok(actions: list[dict[str, object]]) -> bool:
    return bool(actions) and all(action.get("ok") is True for action in actions)


def _build_result_evidence(
    result: CommandResult, *, lines: int = 40
) -> dict[str, object]:
    evidence: dict[str, object] = {
        "command": _release_probe_build_command(),
        "returncode": result.returncode,
    }
    if result.returncode == 0:
        evidence["stdout_tail"] = result.stdout.strip().splitlines()[-lines:]
        evidence["stderr_tail"] = result.stderr.strip().splitlines()[-lines:]
    else:
        evidence["stdout"] = result.stdout
        evidence["stderr"] = result.stderr
    return evidence


def _interrupt_handler(signum: int, _frame: object) -> None:
    signal_name = signal.Signals(signum).name
    raise InterruptedError(f"proof interrupted by {signal_name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--auth-mode",
        type=_login_auth_mode,
        default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", "login"),
        help="Certification uses a stable existing account and only permits login.",
    )
    parser.add_argument(
        "--server-id", default=os.environ.get("SECUREWAVE_RUNTIME_PROBE_SERVER_ID")
    )
    parser.add_argument(
        "--api-base",
        help=(
            "Explicit API base. Production additionally requires "
            "--allow-production."
        ),
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help=(
            "Explicitly authorize a live proof against api.securewaveapp.com. "
            "This may create or reuse the account's VPN device."
        ),
    )
    parser.add_argument(
        "--auth-file",
        default=_env_default(
            "SECUREWAVE_CERT_AUTH_FILE", "SECUREWAVE_LIVE_ACCOUNT_FILE"
        ),
        help=(
            "Optional key=value file for stable live credentials. Defaults to "
            "securewave_private/live_certification_account.env when present."
        ),
    )
    parser.add_argument(
        "--use-mock-api",
        type=_disabled_mock_api,
        default=os.environ.get("SECUREWAVE_USE_MOCK_API", "false"),
    )
    parser.add_argument("--protocol", action="append", choices=SUPPORTED_PROTOCOLS)
    parser.add_argument("--hold-seconds", type=_positive_int, default=60)
    parser.add_argument("--evidence-timeout", type=_positive_int, default=180)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.allow_production:
        os.environ["SECUREWAVE_ALLOW_PRODUCTION_PROOF"] = "true"
    try:
        args.api_base = _canonical_api_base(args.api_base or _default_api_base() or "")
    except argparse.ArgumentTypeError as exc:
        parser.error(str(exc))

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
        security_error = _credential_file_security_error(auth_file_path)
        if security_error:
            payload = {
                "ok": False,
                "account_email": None,
                "auth_mode": args.auth_mode,
                "error": security_error,
                "results": [],
            }
            if args.json:
                print(json.dumps(payload, indent=2, sort_keys=True))
            else:
                print(f"FAIL auth: {security_error}")
            return 2
        credential_values = _parse_env_file(auth_file_path)

    email = _env_default(
        "DEMO_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    ) or _file_default(
        credential_values,
        "DEMO_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    )
    password = _env_default(
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
    ) or _file_default(
        credential_values,
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
    )
    auth_mode = args.auth_mode
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
    if len(protocols) != len(set(protocols)):
        parser.error("each protocol may be requested at most once")
    tools = _required_tools_evidence()
    preflight_cleanup_actions: list[dict[str, object]] = []
    baseline: CommandResult | None = None
    baseline_body: dict[str, object] | None = None
    probe_build: CommandResult | None = None
    probe_app_root: Path | None = None
    probe_binary: Path | None = None
    results: list[dict[str, object]] = []
    cleanup_actions: list[dict[str, object]] = []
    probe_workspace_cleanup: dict[str, object] = {"ok": True, "removed": False}
    run_error: str | None = None
    cleanup: CommandResult
    deferred_signals: list[str] = []

    def defer_interrupt(signum: int, _frame: object) -> None:
        deferred_signals.append(signal.Signals(signum).name)

    previous_handlers = {
        signum: signal.getsignal(signum) for signum in (signal.SIGINT, signal.SIGTERM)
    }
    for signum in previous_handlers:
        signal.signal(signum, _interrupt_handler)
    try:
        if not tools["ok"]:
            run_error = "missing required tools: " + ", ".join(tools["missing"])
        else:
            for protocol in SUPPORTED_PROTOCOLS:
                preflight_cleanup_actions.extend(_cleanup_protocol_residue(protocol))
            if not _cleanup_actions_ok(preflight_cleanup_actions):
                run_error = (
                    "preflight cleanup failed or returned a helper contract older than "
                    f"{MINIMUM_HELPER_CONTRACT}"
                )
            else:
                baseline = _verifier()
                baseline_body = _json_object(baseline.stdout)
                if not _verifier_succeeded(baseline):
                    run_error = "baseline runtime verifier failed"
                else:
                    try:
                        probe_app_root = _prepare_probe_workspace()
                        probe_build = _build_release_probe(probe_app_root)
                        if probe_build.returncode != 0:
                            run_error = "release runtime probe build failed"
                        else:
                            probe_binary = _probe_binary_path(probe_app_root)
                            if not probe_binary.is_file() or not os.access(
                                probe_binary, os.X_OK
                            ):
                                run_error = (
                                    "release runtime probe binary is missing or not "
                                    f"executable: {probe_binary}"
                                )
                    except (InterruptedError, KeyboardInterrupt):
                        raise
                    except Exception as exc:  # noqa: BLE001 - preserve build blocker.
                        run_error = (
                            "unable to prepare isolated release runtime probe: "
                            f"{type(exc).__name__}: {exc}"
                        )
                if run_error is None and probe_binary is not None:
                    for protocol in protocols:
                        try:
                            result = run_protocol(
                                probe_binary=probe_binary,
                                protocol=protocol,
                                email=email,
                                password=password,
                                auth_mode=auth_mode,
                                server_id=args.server_id,
                                hold_seconds=args.hold_seconds,
                                evidence_timeout=args.evidence_timeout,
                                api_base=args.api_base,
                                use_mock_api=args.use_mock_api,
                            )
                        except Exception as exc:  # noqa: BLE001 - retain exact blocker.
                            result = {
                                "protocol": protocol,
                                "ok": False,
                                "command": _build_probe_command(probe_binary),
                                "error": _redact_sensitive_text(
                                    str(exc), email=email, password=password
                                ),
                                "error_type": type(exc).__name__,
                            }
                        results.append(result)
                        if result.get("ok") is not True:
                            run_error = f"{protocol} proof failed"
                            break
    except (InterruptedError, KeyboardInterrupt) as exc:
        run_error = str(exc)
    finally:
        for signum in previous_handlers:
            signal.signal(signum, defer_interrupt)
        for protocol in SUPPORTED_PROTOCOLS:
            try:
                cleanup_actions.extend(_cleanup_protocol_residue(protocol))
            except Exception as exc:  # noqa: BLE001 - continue remaining finalizers.
                cleanup_actions.append(
                    {
                        "protocol": protocol,
                        "ok": False,
                        "error": f"cleanup raised {type(exc).__name__}: {exc}",
                    }
                )
        try:
            cleanup = _verifier()
        except Exception as exc:  # noqa: BLE001 - temp cleanup must still run.
            cleanup = CommandResult(
                1,
                "",
                f"final verifier raised {type(exc).__name__}: {exc}",
            )
        try:
            probe_workspace_cleanup = _remove_probe_workspace(probe_app_root)
        except Exception as exc:  # noqa: BLE001 - report cleanup failure.
            probe_workspace_cleanup = {
                "ok": False,
                "removed": False,
                "error": f"workspace cleanup raised {type(exc).__name__}: {exc}",
            }
        if deferred_signals:
            deferred_error = "proof interrupted during final cleanup by " + ", ".join(
                deferred_signals
            )
            run_error = (
                f"{run_error}; {deferred_error}" if run_error else deferred_error
            )
        for signum, previous_handler in previous_handlers.items():
            signal.signal(signum, previous_handler)

    payload = {
        "ok": (
            run_error is None
            and len(results) == len(protocols)
            and all(result.get("ok") is True for result in results)
            and _cleanup_actions_ok(cleanup_actions)
            and _verifier_succeeded(cleanup)
            and probe_workspace_cleanup.get("ok") is True
        ),
        "account_email": _redact_email(email),
        "auth_mode": auth_mode,
        "protocols": protocols,
        "required_tools": tools,
        "error": run_error,
        "preflight_cleanup_actions": preflight_cleanup_actions,
        "baseline_command": _verifier_command(),
        "baseline": baseline.as_dict() if baseline is not None else None,
        "baseline_checks": baseline_body,
        "probe_build": (
            _build_result_evidence(probe_build) if probe_build is not None else None
        ),
        "probe_binary": str(probe_binary) if probe_binary is not None else None,
        "probe_workspace_isolated": bool(
            probe_app_root is not None and probe_app_root.parent != APP_ROOT.parent
        ),
        "probe_workspace_cleanup": probe_workspace_cleanup,
        "results": results,
        "cleanup_actions": cleanup_actions,
        "cleanup_command": _verifier_command(),
        "cleanup": cleanup.as_dict(),
        "cleanup_checks": _json_object(cleanup.stdout),
    }
    payload = _redact_sensitive_value(payload, email=email, password=password)
    if not isinstance(payload, dict):
        raise AssertionError("proof payload redaction changed its top-level type")
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for result in results:
            status = "OK" if result["ok"] else "FAIL"
            print(f"{status} {result['protocol']}")
        print("OK cleanup" if _verifier_succeeded(cleanup) else "FAIL cleanup")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
