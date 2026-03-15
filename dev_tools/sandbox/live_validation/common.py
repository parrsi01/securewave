"""Shared utilities for live network validation harnesses."""

from __future__ import annotations

import csv
import ipaddress
import json
import os
import shlex
import socket
import ssl
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

DEFAULT_TEST_SPLIT_TUNNEL_ALLOWED_IPS = (
    "10.0.0.0/8",
    "172.16.0.0/12",
)
TEST_ROUTE_GUARD_START = "# SECUREWAVE_TEST_ROUTE_GUARD_START"
TEST_ROUTE_GUARD_END = "# SECUREWAVE_TEST_ROUTE_GUARD_END"
AUTH_REGISTER_PATH = "/auth/register"
AUTH_LOGIN_PATH = "/auth/login"
AUTH_REFRESH_PATH = "/auth/refresh"


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


def _bool_env_optional(name: str) -> bool | None:
    raw = os.getenv(name)
    if raw is None:
        return None
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _should_allow_insecure_tls(url: str) -> bool:
    parsed = urlparse.urlparse(url.strip())
    if parsed.scheme.lower() != "https":
        return False

    explicit = _bool_env_optional("LIVE_VALIDATION_INSECURE_TLS")
    if explicit is not None:
        return explicit
    explicit = _bool_env_optional("LIVE_API_INSECURE_TLS")
    if explicit is not None:
        return explicit

    host = (parsed.hostname or "").strip().lower()
    if not host:
        return False
    if host.endswith(".nip.io") or host.endswith(".sslip.io"):
        return True
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


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
    context = ssl._create_unverified_context() if _should_allow_insecure_tls(url) else None
    try:
        with urlrequest.urlopen(req, timeout=timeout_seconds, context=context) as response:
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


def resolve_api_host(api_base_url: str) -> str | None:
    try:
        parsed = urlparse.urlparse(api_base_url.strip())
    except Exception:
        return None
    host = (parsed.hostname or "").strip()
    if not host:
        return None
    lowered = host.lower()
    if lowered in {"localhost", "127.0.0.1", "::1", "[::1]"}:
        return None
    return host


def resolve_api_ipv4s(api_base_url: str) -> list[str]:
    host = resolve_api_host(api_base_url)
    if not host:
        return []
    try:
        ipaddress.ip_address(host)
        return [host]
    except ValueError:
        pass

    values: set[str] = set()
    try:
        infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    except Exception:
        return []
    for info in infos:
        try:
            values.add(str(info[4][0]))
        except Exception:
            continue
    return sorted(values)


def wireguard_config_has_full_tunnel(config_text: str) -> bool:
    sections = parse_wireguard_config(config_text)
    allowed = str((sections.get("peer") or {}).get("allowedips") or "")
    values = {item.strip() for item in allowed.split(",") if item.strip()}
    return "0.0.0.0/0" in values or "::/0" in values


def build_wireguard_test_config(
    config_text: str,
    *,
    api_base_url: str,
    enable_split_tunnel: bool = False,
    split_tunnel_allowed_ips: list[str] | tuple[str, ...] | None = None,
) -> tuple[str, dict[str, Any]]:
    normalized = config_text.replace("\r\n", "\n").replace("\r", "\n")
    lines = _strip_managed_route_guard(normalized.split("\n"))
    split_allowed_ips = [
        item.strip()
        for item in (split_tunnel_allowed_ips or DEFAULT_TEST_SPLIT_TUNNEL_ALLOWED_IPS)
        if str(item).strip()
    ]
    split_applied = False
    if enable_split_tunnel and split_allowed_ips:
        lines, split_applied = _rewrite_allowed_ips_for_testing(lines, split_allowed_ips)

    host = resolve_api_host(api_base_url)
    api_ips = resolve_api_ipv4s(api_base_url)
    route_guard_added = False
    if host:
        insert_at = _find_peer_insert_index(lines)
        route_guard_added = True
        lines = [
            *lines[:insert_at],
            *_build_test_route_guard_block(host),
            *lines[insert_at:],
        ]

    return (
        "\n".join(lines).strip() + "\n",
        {
            "api_host": host,
            "api_ips": api_ips,
            "route_guard_added": route_guard_added,
            "split_tunnel_applied": split_applied,
            "split_tunnel_allowed_ips": split_allowed_ips if split_applied else [],
        },
    )


def linux_route_snapshot(api_ip: str | None = None, *, interface: str | None = None) -> dict[str, Any]:
    snapshot = {
        "main_default": run_command(["ip", "route", "show", "default"], timeout_seconds=5).__dict__,
        "main_table": run_command(["ip", "route"], timeout_seconds=5).__dict__,
        "policy_rules": run_command(["ip", "rule", "show"], timeout_seconds=5).__dict__,
        "table_51820": run_command(["ip", "route", "show", "table", "51820"], timeout_seconds=5).__dict__,
    }
    if api_ip:
        snapshot["api_route_get"] = run_command(
            ["ip", "route", "get", api_ip],
            timeout_seconds=5,
        ).__dict__
    if interface:
        snapshot["wg_show"] = run_command(
            ["wg", "show", interface],
            timeout_seconds=5,
        ).__dict__
    return snapshot


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


def _strip_managed_route_guard(lines: list[str]) -> list[str]:
    next_lines: list[str] = []
    skipping = False
    for raw in lines:
        trimmed = raw.strip()
        if trimmed == TEST_ROUTE_GUARD_START:
            skipping = True
            continue
        if trimmed == TEST_ROUTE_GUARD_END:
            skipping = False
            continue
        if not skipping:
            next_lines.append(raw)
    return next_lines


def _find_peer_insert_index(lines: list[str]) -> int:
    for index, raw in enumerate(lines):
        if raw.strip().lower() == "[peer]":
            return index
    return len(lines)


def _build_test_route_guard_block(host: str) -> list[str]:
    pre_up = (
        'PreUp = /bin/sh -c "'
        f'API_HOST=\\"{host}\\"; '
        'API_IPS=\\$(getent ahostsv4 \\"\\$API_HOST\\" | awk \'{print \\$1}\' | sort -u); '
        'GW=\\$(ip route show default 0.0.0.0/0 | awk \'{print \\$3; exit}\'); '
        'DEV=\\$(ip route show default 0.0.0.0/0 | awk \'{print \\$5; exit}\'); '
        '[ -n \\"\\$GW\\" ] && [ -n \\"\\$DEV\\" ] || exit 0; '
        'for ip in \\$API_IPS; do ip route replace \\"\\$ip/32\\" via \\"\\$GW\\" dev \\"\\$DEV\\" metric 5; done"'
    )
    post_down = (
        'PostDown = /bin/sh -c "'
        f'API_HOST=\\"{host}\\"; '
        'API_IPS=\\$(getent ahostsv4 \\"\\$API_HOST\\" | awk \'{print \\$1}\' | sort -u); '
        'for ip in \\$API_IPS; do ip route del \\"\\$ip/32\\" 2>/dev/null || true; done"'
    )
    return [
        TEST_ROUTE_GUARD_START,
        pre_up,
        post_down,
        TEST_ROUTE_GUARD_END,
        "",
    ]


def _rewrite_allowed_ips_for_testing(
    lines: list[str],
    split_allowed_ips: list[str],
) -> tuple[list[str], bool]:
    next_lines: list[str] = []
    in_peer = False
    replaced = False
    replacement = ", ".join(split_allowed_ips)
    for raw in lines:
        stripped = raw.strip()
        lowered = stripped.lower()
        if lowered == "[peer]":
            in_peer = True
            next_lines.append(raw)
            continue
        if stripped.startswith("[") and stripped.endswith("]") and lowered != "[peer]":
            in_peer = False
            next_lines.append(raw)
            continue
        if in_peer and "=" in stripped:
            key, value = stripped.split("=", 1)
            if key.strip().lower() == "allowedips":
                values = {item.strip() for item in value.split(",") if item.strip()}
                if "0.0.0.0/0" in values or "::/0" in values:
                    next_lines.append(f"AllowedIPs = {replacement}")
                    replaced = True
                    continue
        next_lines.append(raw)
    return next_lines, replaced
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


def detect_linux_active_tunnels() -> list[dict[str, str]]:
    result = run_command(["ip", "-o", "link", "show", "up"], timeout_seconds=5)
    if result.returncode != 0:
        return []

    tunnels: list[dict[str, str]] = []
    for raw in result.stdout.splitlines():
        parts = raw.split(":", 2)
        if len(parts) < 2:
            continue
        iface = parts[1].strip().split("@", 1)[0]
        if not iface.startswith(("wg", "tun", "utun")):
            continue
        tunnels.append({"interface": iface, "link": raw.strip()})
    return tunnels


def linux_runtime_preflight(
    *,
    api_base_url: str,
    public_ip_endpoint: str = "https://api.ipify.org",
) -> dict[str, Any]:
    api_host = resolve_api_host(api_base_url)
    api_ips = resolve_api_ipv4s(api_base_url)
    active_tunnels = detect_linux_active_tunnels()
    is_root = bool(getattr(os, "geteuid", lambda: -1)() == 0)

    preflight: dict[str, Any] = {
        "platform": "linux",
        "api_host": api_host,
        "api_ips": api_ips,
        "public_ip": fetch_public_ip(endpoint=public_ip_endpoint),
        "default_route": run_command(["ip", "route", "show", "default"], timeout_seconds=5).__dict__,
        "routes": run_command(["ip", "route"], timeout_seconds=5).__dict__,
        "addresses": run_command(["ip", "addr"], timeout_seconds=5).__dict__,
        "wg_show": run_command(["wg", "show"], timeout_seconds=5).__dict__,
        "resolvectl_status": run_command(["resolvectl", "status"], timeout_seconds=8).__dict__,
        "active_tunnels": active_tunnels,
        "is_root": is_root,
        "failures": [],
    }

    failures: list[str] = []
    if active_tunnels:
        tunnels = ", ".join(item["interface"] for item in active_tunnels)
        failures.append(f"active_tunnels_detected:{tunnels}")
    if not is_root:
        failures.append("linux_validation_requires_root")

    preflight["failures"] = failures
    preflight["can_continue"] = len(failures) == 0
    return preflight


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


def normalize_api_base_url(api_base_url: str) -> str:
    raw = api_base_url.strip().rstrip("/")
    if not raw:
        return ""

    parsed = urlparse.urlparse(raw)
    path = parsed.path.rstrip("/")
    if not path:
        api_path = "/api"
    elif path.endswith("/api"):
        api_path = path
    else:
        api_path = f"{path}/api"

    normalized = parsed._replace(path=api_path, params="", query="", fragment="")
    return urlparse.urlunparse(normalized).rstrip("/")


def build_api_url(api_base_url: str, path: str) -> str:
    base = normalize_api_base_url(api_base_url)
    suffix = "/" + path.lstrip("/")
    return f"{base}{suffix}"


def auth_endpoint_urls(api_base_url: str) -> dict[str, str]:
    return {
        "register": build_api_url(api_base_url, AUTH_REGISTER_PATH),
        "login": build_api_url(api_base_url, AUTH_LOGIN_PATH),
        "refresh": build_api_url(api_base_url, AUTH_REFRESH_PATH),
    }


def _auth_response_summary(body: dict[str, Any] | str) -> dict[str, Any] | str:
    if not isinstance(body, dict):
        return str(body)[:240]

    summary: dict[str, Any] = {}
    for key in ("message", "detail", "requires_2fa", "email_sent", "user_id", "email"):
        if key in body:
            summary[key] = body[key]
    if "error" in body:
        summary["error"] = body["error"]
    return summary


def _auth_meta(
    *,
    source: str,
    endpoints: dict[str, str],
    register: HttpResult,
    register_body: dict[str, Any] | str,
    register_token: str,
    login: HttpResult,
    login_body: dict[str, Any] | str,
    login_token: str,
    refresh: HttpResult | None = None,
    refresh_body: dict[str, Any] | str | None = None,
    refresh_token: str = "",
    fallback: HttpResult | None = None,
    fallback_body: dict[str, Any] | str | None = None,
    fallback_token: str = "",
    fallback_email: str | None = None,
) -> dict[str, Any]:
    return {
        "source": source,
        "endpoints": endpoints,
        "register_status": register.status_code,
        "register_token_received": bool(register_token),
        "register_response": _auth_response_summary(register_body),
        "login_status": login.status_code,
        "login_token_received": bool(login_token),
        "login_response": _auth_response_summary(login_body),
        "refresh_status": refresh.status_code if refresh else None,
        "refresh_token_received": bool(refresh_token),
        "refresh_response": _auth_response_summary(refresh_body) if refresh is not None else None,
        "fallback_status": fallback.status_code if fallback else None,
        "fallback_token_received": bool(fallback_token),
        "fallback_response": _auth_response_summary(fallback_body) if fallback is not None else None,
        "fallback_email": fallback_email,
    }


def register_or_login_user(
    *,
    api_base_url: str,
    email: str,
    password: str,
    timeout_seconds: int,
) -> tuple[bool, str | None, dict[str, Any]]:
    endpoints = auth_endpoint_urls(api_base_url)
    register_payload = {
        "email": email,
        "password": password,
        "password_confirm": password,
    }
    register = http_json_request(
        "POST",
        endpoints["register"],
        payload=register_payload,
        timeout_seconds=timeout_seconds,
    )
    register_body = register.body if isinstance(register.body, dict) else {}
    register_token = str(register_body.get("access_token") or "")
    register_refresh_token = str(register_body.get("refresh_token") or "")

    login = http_json_request(
        "POST",
        endpoints["login"],
        payload={"email": email, "password": password},
        timeout_seconds=timeout_seconds,
    )
    login_body = login.body if isinstance(login.body, dict) else {}
    login_token = str(login_body.get("access_token") or "")
    if login.status_code == 200 and login_token:
        return True, login_token, _auth_meta(
            source="login",
            endpoints=endpoints,
            register=register,
            register_body=register_body,
            register_token=register_token,
            login=login,
            login_body=login_body,
            login_token=login_token,
        )

    refresh: HttpResult | None = None
    refresh_body: dict[str, Any] | str | None = None
    refresh_token = ""
    if register.status_code in {200, 201} and register_refresh_token:
        refresh = http_json_request(
            "POST",
            endpoints["refresh"],
            payload={"refresh_token": register_refresh_token},
            timeout_seconds=timeout_seconds,
        )
        refresh_body = refresh.body if isinstance(refresh.body, dict) else refresh.body
        refresh_token = str((refresh.body if isinstance(refresh.body, dict) else {}).get("access_token") or "")
        if refresh.status_code == 200 and refresh_token:
            return True, refresh_token, _auth_meta(
                source="refresh",
                endpoints=endpoints,
                register=register,
                register_body=register_body,
                register_token=register_token,
                login=login,
                login_body=login_body,
                login_token=login_token,
                refresh=refresh,
                refresh_body=refresh_body,
                refresh_token=refresh_token,
            )

    if register.status_code in {200, 201} and register_token:
        return True, register_token, _auth_meta(
            source="register",
            endpoints=endpoints,
            register=register,
            register_body=register_body,
            register_token=register_token,
            login=login,
            login_body=login_body,
            login_token=login_token,
            refresh=refresh,
            refresh_body=refresh_body,
            refresh_token=refresh_token,
        )

    fallback_email = (os.getenv("LIVE_VALIDATION_FALLBACK_EMAIL") or "securewave_test_user@example.com").strip()
    fallback_password = os.getenv("LIVE_VALIDATION_FALLBACK_PASSWORD") or "SecureWaveTest123"
    if fallback_email and fallback_password and (fallback_email != email or fallback_password != password):
        fallback = http_json_request(
            "POST",
            endpoints["login"],
            payload={"email": fallback_email, "password": fallback_password},
            timeout_seconds=timeout_seconds,
        )
        fallback_body = fallback.body if isinstance(fallback.body, dict) else {}
        fallback_token = str(fallback_body.get("access_token") or "")
        if fallback.status_code == 200 and fallback_token:
            return True, fallback_token, _auth_meta(
                source="fallback_login",
                endpoints=endpoints,
                register=register,
                register_body=register_body,
                register_token=register_token,
                login=login,
                login_body=login_body,
                login_token=login_token,
                refresh=refresh,
                refresh_body=refresh_body,
                refresh_token=refresh_token,
                fallback=fallback,
                fallback_body=fallback_body,
                fallback_token=fallback_token,
                fallback_email=fallback_email,
            )

    detail = _auth_meta(
        source="login",
        endpoints=endpoints,
        register=register,
        register_body=register_body,
        register_token=register_token,
        login=login,
        login_body=login_body,
        login_token=login_token,
        refresh=refresh,
        refresh_body=refresh_body,
        refresh_token=refresh_token,
    )
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
        build_api_url(api_base_url, "/vpn/profile"),
        payload=payload,
        headers={"Authorization": f"Bearer {access_token}"},
        timeout_seconds=timeout_seconds,
    )
