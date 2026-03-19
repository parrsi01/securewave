from __future__ import annotations

import csv
import json
import shutil
import socket
import subprocess  # nosec B404 - controlled local operator tooling
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS_ROOT = REPO_ROOT / "artifacts" / "local_agents"
DATA_ROOT = REPO_ROOT / "data" / "local_agents"


def utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass
class CommandResult:
    command: str
    returncode: int
    stdout: str
    stderr: str
    duration_ms: float

    @property
    def ok(self) -> bool:
        return self.returncode == 0


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(
    command: Sequence[str] | str,
    *,
    timeout_seconds: float = 8.0,
    shell: bool = False,
) -> CommandResult:
    started = time.monotonic()
    proc = subprocess.run(  # nosec B603
        command,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
        shell=shell,
    )
    return CommandResult(
        command=command if isinstance(command, str) else " ".join(command),
        returncode=proc.returncode,
        stdout=proc.stdout.strip(),
        stderr=proc.stderr.strip(),
        duration_ms=round((time.monotonic() - started) * 1000, 2),
    )


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def append_csv_row(path: Path, fieldnames: Sequence[str], row: dict[str, Any]) -> None:
    ensure_dir(path.parent)
    exists = path.exists()
    with path.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if not exists:
            writer.writeheader()
        writer.writerow(row)


def load_json(path: Path, default: dict[str, Any] | None = None) -> dict[str, Any]:
    if not path.exists():
        return dict(default or {})
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return dict(default or {})


def write_json(path: Path, payload: dict[str, Any]) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_recent_jsonl(path: Path, *, limit: int = 50) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()[-limit:]
    records: list[dict[str, Any]] = []
    for line in lines:
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def _health_url(api_base_url: str) -> str:
    base = api_base_url.rstrip("/")
    if base.endswith("/api"):
        return f"{base}/health"
    if "/api/" in base:
        return f"{base.split('/api/', 1)[0]}/api/health"
    return f"{base}/api/health"


def _timed_http_ok(url: str, *, timeout_seconds: float = 5.0) -> tuple[bool, float | None]:
    started = time.monotonic()
    try:
        req = Request(url, method="GET")
        with urlopen(req, timeout=timeout_seconds) as resp:  # nosec - local validation tooling
            ok = 200 <= resp.status < 300
            latency = round((time.monotonic() - started) * 1000, 2)
            return ok, latency
    except HTTPError as exc:
        latency = round((time.monotonic() - started) * 1000, 2)
        return 200 <= exc.code < 300, latency
    except (URLError, OSError, TimeoutError):
        return False, None


def internet_reachable(*, timeout_seconds: float = 3.0) -> bool:
    targets = (("1.1.1.1", 443), ("8.8.8.8", 53))
    for host, port in targets:
        try:
            with socket.create_connection((host, port), timeout=timeout_seconds):
                return True
        except OSError:
            continue
    return False


def dns_resolves(hostname: str = "example.com") -> bool:
    try:
        socket.getaddrinfo(hostname, None)
        return True
    except OSError:
        return False


def interface_is_up(interface: str) -> bool:
    if not command_exists("ip"):
        return False
    result = run_command(["ip", "link", "show", interface], timeout_seconds=4.0)
    text = result.stdout
    if not result.ok or not text:
        return False
    return "state UP" in text or "<" in text and "UP" in text.split("<", 1)[1].split(">", 1)[0]


def default_route_present() -> bool:
    if not command_exists("ip"):
        return False
    result = run_command(["ip", "route", "show", "default"], timeout_seconds=4.0)
    return result.ok and bool(result.stdout.strip())


def read_interface_bytes(interface: str) -> tuple[int | None, int | None]:
    stats_root = Path("/sys/class/net") / interface / "statistics"
    try:
        rx = int((stats_root / "rx_bytes").read_text(encoding="utf-8").strip())
        tx = int((stats_root / "tx_bytes").read_text(encoding="utf-8").strip())
        return rx, tx
    except Exception:
        return None, None


def active_network_connections() -> tuple[list[str], bool | None, bool | None, bool | None]:
    if not command_exists("nmcli"):
        return [], None, None, None

    active = run_command(
        ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"],
        timeout_seconds=5.0,
    )
    wifi_radio = run_command(["nmcli", "radio", "wifi"], timeout_seconds=5.0)

    active_names: list[str] = []
    wifi_connected = False
    ethernet_connected = False
    if active.ok:
        for line in active.stdout.splitlines():
            parts = [item.strip() for item in line.split(":")]
            if len(parts) < 3:
                continue
            name, conn_type, device = parts[:3]
            if name:
                active_names.append(name)
            if conn_type == "wifi" and device:
                wifi_connected = True
            if conn_type == "ethernet" and device:
                ethernet_connected = True

    wifi_enabled = None
    if wifi_radio.ok:
        wifi_enabled = wifi_radio.stdout.strip().lower() == "enabled"

    return active_names, wifi_enabled, wifi_connected, ethernet_connected


def preferred_wifi_connection_name() -> str | None:
    if not command_exists("nmcli"):
        return None
    result = run_command(
        ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"],
        timeout_seconds=5.0,
    )
    if not result.ok:
        return None
    for line in result.stdout.splitlines():
        parts = [item.strip() for item in line.split(":")]
        if len(parts) >= 2 and parts[1] == "wifi":
            return parts[0] or None
    return None


@dataclass
class ConnectivitySnapshot:
    timestamp: str
    interface: str
    vpn_interface_up: bool
    default_route_present: bool
    internet_reachable: bool
    dns_ok: bool
    api_health_ok: bool
    api_latency_ms: float | None
    wifi_radio_enabled: bool | None
    wifi_connected: bool | None
    ethernet_connected: bool | None
    active_connections: list[str] = field(default_factory=list)
    rx_bytes: int | None = None
    tx_bytes: int | None = None
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def collect_connectivity_snapshot(
    *,
    api_base_url: str,
    interface: str,
    extra_notes: Iterable[str] | None = None,
) -> ConnectivitySnapshot:
    active, wifi_radio_enabled, wifi_connected, ethernet_connected = active_network_connections()
    api_health_ok, api_latency_ms = _timed_http_ok(_health_url(api_base_url)) if api_base_url else (False, None)
    rx_bytes, tx_bytes = read_interface_bytes(interface)
    notes = list(extra_notes or [])
    if not active:
        notes.append("no_active_nm_connections")
    if wifi_radio_enabled is False:
        notes.append("wifi_radio_disabled")
    if not default_route_present():
        notes.append("default_route_missing")
    if interface and not interface_is_up(interface):
        notes.append("vpn_interface_down")

    return ConnectivitySnapshot(
        timestamp=utc_now_iso(),
        interface=interface,
        vpn_interface_up=interface_is_up(interface),
        default_route_present=default_route_present(),
        internet_reachable=internet_reachable(),
        dns_ok=dns_resolves(),
        api_health_ok=api_health_ok,
        api_latency_ms=api_latency_ms,
        wifi_radio_enabled=wifi_radio_enabled,
        wifi_connected=wifi_connected,
        ethernet_connected=ethernet_connected,
        active_connections=active,
        rx_bytes=rx_bytes,
        tx_bytes=tx_bytes,
        notes=notes,
    )


def derive_bandwidth_mbps(
    *,
    previous_rx_bytes: int | None,
    previous_tx_bytes: int | None,
    current_rx_bytes: int | None,
    current_tx_bytes: int | None,
    elapsed_seconds: float,
) -> float:
    if not previous_rx_bytes or not previous_tx_bytes:
        return 0.0
    if not current_rx_bytes or not current_tx_bytes:
        return 0.0
    if elapsed_seconds <= 0:
        return 0.0
    delta_bytes = max(0, current_rx_bytes - previous_rx_bytes) + max(0, current_tx_bytes - previous_tx_bytes)
    return round((delta_bytes * 8.0) / max(elapsed_seconds, 1e-6) / 1_000_000.0, 3)


def api_host(api_base_url: str) -> str:
    parsed = urlparse(api_base_url)
    return parsed.hostname or ""
