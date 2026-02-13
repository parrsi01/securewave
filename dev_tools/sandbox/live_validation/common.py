"""Shared utilities for live network validation harnesses."""

from __future__ import annotations

import csv
import ipaddress
import json
import os
import shlex
import socket
import statistics
import subprocess  # nosec B404 - operator-controlled live validation commands
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error as urlerror
from urllib import parse as urlparse
from urllib import request as urlrequest


@dataclass
class CommandResult:
    command: str
    returncode: int
    stdout: str
    stderr: str
    duration_ms: float


@dataclass
class HttpResult:
    status_code: int
    body: dict[str, Any] | str
    duration_ms: float


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_dir(path: str | Path) -> Path:
    out = Path(path)
    out.mkdir(parents=True, exist_ok=True)
    return out


def write_json(path: str | Path, payload: Any) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return target


def write_csv(path: str | Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return target


def write_markdown(path: str | Path, content: str) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return target


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    idx = (len(ordered) - 1) * (pct / 100.0)
    lower = int(idx)
    upper = min(lower + 1, len(ordered) - 1)
    interp = idx - lower
    return float(ordered[lower] + (ordered[upper] - ordered[lower]) * interp)


def mean(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(sum(values) / len(values))


def stdev(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    return float(statistics.pstdev(values))


def bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def run_command(
    command: list[str] | str,
    *,
    timeout_seconds: int = 20,
    env: dict[str, str] | None = None,
    cwd: str | None = None,
    shell: bool = False,
) -> CommandResult:
    started = time.monotonic()
    if isinstance(command, list):
        cmd_display = " ".join(shlex.quote(part) for part in command)
    else:
        cmd_display = command
    try:
        proc = subprocess.run(  # nosec B603
            command,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
            env=env,
            cwd=cwd,
            shell=shell,
        )
    except Exception as exc:  # pragma: no cover - env dependent
        return CommandResult(
            command=cmd_display,
            returncode=1,
            stdout="",
            stderr=str(exc),
            duration_ms=round((time.monotonic() - started) * 1000, 3),
        )
    return CommandResult(
        command=cmd_display,
        returncode=proc.returncode,
        stdout=(proc.stdout or "").strip(),
        stderr=(proc.stderr or "").strip(),
        duration_ms=round((time.monotonic() - started) * 1000, 3),
    )


def _json_loads_maybe(text: str) -> dict[str, Any] | str:
    try:
        parsed = json.loads(text)
    except Exception:
        return text
    if isinstance(parsed, dict):
        return parsed
    return text


def http_json_request(
    method: str,
    url: str,
    *,
    payload: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout_seconds: int = 15,
) -> HttpResult:
    body_bytes = None
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    if payload is not None:
        body_bytes = json.dumps(payload).encode("utf-8")

    req = urlrequest.Request(url=url, method=method.upper(), data=body_bytes, headers=request_headers)
    started = time.monotonic()
    try:
        with urlrequest.urlopen(req, timeout=timeout_seconds) as response:
            raw_body = response.read().decode("utf-8", errors="replace")
            status = int(response.status)
    except urlerror.HTTPError as exc:
        raw_body = exc.read().decode("utf-8", errors="replace") if exc.fp else str(exc)
        status = int(exc.code)
    except Exception as exc:  # pragma: no cover - environment dependent
        return HttpResult(status_code=0, body=str(exc), duration_ms=round((time.monotonic() - started) * 1000, 3))

    return HttpResult(
        status_code=status,
        body=_json_loads_maybe(raw_body),
        duration_ms=round((time.monotonic() - started) * 1000, 3),
    )


def redact(value: str | None) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "***"
    return f"{value[:4]}***{value[-3:]}"


def parse_wireguard_config(config_text: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = ""
    for raw in config_text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip().lower()
            sections.setdefault(current, {})
            continue
        if "=" not in line or not current:
            continue
        key, value = line.split("=", 1)
        sections[current][key.strip().lower()] = value.strip()
    return sections


def build_interface_name(prefix: str, index: int) -> str:
    candidate = f"{prefix}{index}"
    # Linux interface names max out at 15 chars.
    return candidate[:15]


def parse_latest_handshake_epoch(output: str, peer_public_key: str | None = None) -> int:
    best = 0
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        key = parts[0]
        ts_raw = parts[1]
        if peer_public_key and key != peer_public_key:
            continue
        try:
            epoch = int(ts_raw)
        except ValueError:
            continue
        if epoch > best:
            best = epoch
    return best


def resolve_host_from_url(url: str) -> str | None:
    try:
        parsed = urlparse.urlparse(url)
    except Exception:
        return None
    host = parsed.hostname
    if not host:
        return None
    try:
        return socket.gethostbyname(host)
    except Exception:
        return None


def fetch_public_ip(*, endpoint: str = "https://api.ipify.org", timeout_seconds: int = 8) -> str | None:
    req = urlrequest.Request(endpoint, headers={"User-Agent": "securewave-live-validation/1.0"})
    try:
        with urlrequest.urlopen(req, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8", errors="replace").strip()
    except Exception:
        return None
    try:
        ipaddress.ip_address(raw)
    except ValueError:
        return None
    return raw


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


def evaluate_dns_leak(observed: list[str], allowed: set[str], *, allow_private: bool = True) -> tuple[bool, list[str]]:
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


def read_text(path: str | Path) -> str:
    target = Path(path)
    if not target.exists():
        return ""
    return target.read_text(encoding="utf-8", errors="ignore")


def register_or_login_user(
    *,
    api_base_url: str,
    email: str,
    password: str,
    timeout_seconds: int,
) -> tuple[bool, str | None, dict[str, Any]]:
    register_payload = {
        "email": email,
        "password": password,
        "password_confirm": password,
    }
    register = http_json_request(
        "POST",
        f"{api_base_url.rstrip('/')}/api/auth/register",
        payload=register_payload,
        timeout_seconds=timeout_seconds,
    )
    register_body = register.body if isinstance(register.body, dict) else {}
    token = str(register_body.get("access_token") or "")
    if register.status_code in {200, 201} and token:
        return True, token, {"source": "register", "status_code": register.status_code}

    login = http_json_request(
        "POST",
        f"{api_base_url.rstrip('/')}/api/auth/login",
        payload={"email": email, "password": password},
        timeout_seconds=timeout_seconds,
    )
    login_body = login.body if isinstance(login.body, dict) else {}
    token = str(login_body.get("access_token") or "")
    if login.status_code == 200 and token:
        return True, token, {"source": "login", "status_code": login.status_code}

    detail = {
        "source": "login",
        "register_status": register.status_code,
        "login_status": login.status_code,
    }
    return False, None, detail


def fetch_vpn_profile(
    *,
    api_base_url: str,
    access_token: str,
    device_name: str,
    device_type: str,
    timeout_seconds: int,
    server_id: str | None = None,
) -> HttpResult:
    payload: dict[str, Any] = {
        "device_name": device_name,
        "device_type": device_type,
        "protocol": "wireguard",
    }
    if server_id:
        payload["server_id"] = server_id

    return http_json_request(
        "POST",
        f"{api_base_url.rstrip('/')}/api/vpn/profile",
        payload=payload,
        headers={"Authorization": f"Bearer {access_token}"},
        timeout_seconds=timeout_seconds,
    )
