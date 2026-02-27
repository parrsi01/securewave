from __future__ import annotations
import contextlib
import fcntl
import logging
import subprocess
import time
from pathlib import Path

logger = logging.getLogger(__name__)
_LOCK_PATH = Path("/tmp/securewave_netstate.lock")
_LOCK_TIMEOUT_SECONDS = 10.0
_RT_TABLES = Path("/etc/iproute2/rt_tables")
_CONFIG = {
    "wireguard": {"table": "100", "iface": "wg0", "fwmark": "0x64", "iif_prio": "10100", "mark_prio": "10101"},
    "openvpn": {"table": "200", "iface": "tun0", "fwmark": "0xc8", "iif_prio": "10200", "mark_prio": "10201"},
    "ikev2": {"table": "300", "iface": "ipsec0", "fwmark": "0x12c", "iif_prio": "10300", "mark_prio": "10301"},
}


def _run(*args: str) -> bool:
    p = subprocess.run(list(args), capture_output=True, text=True, timeout=10, check=False)  # nosec B603
    return p.returncode == 0


@contextlib.contextmanager
def network_lock(timeout_seconds: float = _LOCK_TIMEOUT_SECONDS):
    _LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK_PATH.open("a+", encoding="utf-8") as h:
        deadline = time.monotonic() + timeout_seconds
        while True:
            try:
                fcntl.flock(h.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError as exc:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Timed out waiting for securewave network lock") from exc
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(h.fileno(), fcntl.LOCK_UN)


def _ensure_rt_table(protocol: str, table: str) -> None:
    entry = f"{table} {protocol}"
    try:
        content = _RT_TABLES.read_text(encoding="utf-8")
    except OSError:
        return
    if entry in content:
        return
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and (parts[0] == table or parts[1] == protocol):
            return
    try:
        with _RT_TABLES.open("a", encoding="utf-8") as h:
            if content and not content.endswith("\n"):
                h.write("\n")
            h.write(f"{entry}\n")
    except OSError:
        return


def _has_ip_rule(*tokens: str) -> bool:
    p = subprocess.run(["ip", "-4", "rule", "show"], capture_output=True, text=True, timeout=10, check=False)  # nosec B603
    return p.returncode == 0 and any(all(t in line for t in tokens) for line in (p.stdout or "").splitlines())


def _main_default_iface() -> str | None:
    p = subprocess.run(["ip", "-4", "route", "show", "default"], capture_output=True, text=True, timeout=10, check=False)  # nosec B603
    parts = (p.stdout or "").split()
    return parts[parts.index("dev") + 1] if "dev" in parts and parts.index("dev") + 1 < len(parts) else None


def _table_default_uses_iface(table: str, iface: str) -> bool:
    p = subprocess.run(["ip", "-4", "route", "show", "table", table, "default"], capture_output=True, text=True, timeout=10, check=False)  # nosec B603
    return p.returncode == 0 and f"dev {iface}" in (p.stdout or "")


def setup_protocol(protocol: str, source_cidr: str, iface: str | None = None) -> None:
    cfg = _CONFIG[protocol]
    table, tunnel_iface = cfg["table"], (iface or cfg["iface"])
    _ensure_rt_table(protocol, table)
    _run("ip", "-4", "route", "replace", source_cidr, "dev", tunnel_iface, "table", table)
    egress_iface = _main_default_iface()
    if egress_iface:
        _run("ip", "-4", "route", "replace", "default", "dev", egress_iface, "table", table)
    if _table_default_uses_iface(table, tunnel_iface):
        raise RuntimeError(f"route_recursion_detected protocol={protocol} table={table} default_dev={tunnel_iface}")
    if not _has_ip_rule(f"priority {cfg['iif_prio']}", f"iif {tunnel_iface}", f"lookup {table}"):
        _run("ip", "-4", "rule", "add", "priority", cfg["iif_prio"], "iif", tunnel_iface, "lookup", table)
    if not _has_ip_rule(f"priority {cfg['mark_prio']}", f"fwmark {cfg['fwmark']}", f"lookup {table}"):
        _run("ip", "-4", "rule", "add", "priority", cfg["mark_prio"], "fwmark", cfg["fwmark"], "lookup", table)


def teardown_protocol(protocol: str, iface: str | None = None) -> None:
    cfg = _CONFIG[protocol]
    table, tunnel_iface = cfg["table"], (iface or cfg["iface"])
    while _has_ip_rule(f"priority {cfg['mark_prio']}", f"fwmark {cfg['fwmark']}", f"lookup {table}"):
        _run("ip", "-4", "rule", "del", "priority", cfg["mark_prio"], "fwmark", cfg["fwmark"], "lookup", table)
    while _has_ip_rule(f"priority {cfg['iif_prio']}", f"iif {tunnel_iface}", f"lookup {table}"):
        _run("ip", "-4", "rule", "del", "priority", cfg["iif_prio"], "iif", tunnel_iface, "lookup", table)
    _run("ip", "-4", "route", "flush", "table", table)
    logger.info("routing teardown protocol=%s table=%s iface=%s", protocol, table, tunnel_iface)
