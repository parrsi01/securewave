from __future__ import annotations

import logging
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

_RT_TABLES = Path("/etc/iproute2/rt_tables")
_PRIORITY = 200
_PROTOCOL_TABLE = {"wireguard": 100, "openvpn": 200, "ikev2": 300}
_PROTOCOL_IFACE = {"wireguard": "wg0", "openvpn": "tun0", "ikev2": "ipsec0"}
_PROTOCOL_CIDR = {
    "wireguard": "10.8.0.0/24",
    "openvpn": "10.44.0.0/24",
    "ikev2": "10.45.0.0/24",
}


def _run(*args: str) -> bool:
    try:
        proc = subprocess.run(  # nosec B603
            list(args),
            capture_output=True,
            timeout=10,
            check=False,
        )
        return proc.returncode == 0
    except Exception:
        return False


def _ensure_rt_table(protocol: str) -> None:
    table = _PROTOCOL_TABLE[protocol]
    entry = f"{table} {protocol}"
    try:
        text = _RT_TABLES.read_text(encoding="utf-8")
    except Exception as exc:
        logger.warning("failed to read %s: %s", _RT_TABLES, exc)
        return
    if entry in text:
        return
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and (parts[0] == str(table) or parts[1] == protocol):
            logger.warning("rt_tables conflict for %s (%s): %s", protocol, table, line)
            return
    try:
        with _RT_TABLES.open("a", encoding="utf-8") as handle:
            if text and not text.endswith("\n"):
                handle.write("\n")
            handle.write(f"{entry}\n")
    except Exception as exc:
        logger.warning("failed to append rt_tables entry for %s: %s", protocol, exc)


def setup_protocol(protocol: str, _egress_iface: str) -> None:
    if protocol not in _PROTOCOL_TABLE:
        raise ValueError(f"Unknown protocol: {protocol!r}")
    table = _PROTOCOL_TABLE[protocol]
    iface = _PROTOCOL_IFACE[protocol]
    cidr = _PROTOCOL_CIDR[protocol]
    _ensure_rt_table(protocol)

    # Routing table is protocol-specific; main/default route is untouched.
    _run("ip", "-4", "route", "replace", cidr, "dev", iface, "table", str(table))

    # Bind traffic that arrived via the tunnel iface to the protocol table.
    has_rule = _run("sh", "-c", f"ip rule show | grep -q 'iif {iface} lookup {table}'")
    if not has_rule:
        _run(
            "ip",
            "rule",
            "add",
            "iif",
            iface,
            "table",
            str(table),
            "priority",
            str(_PRIORITY),
        )


def teardown_protocol(protocol: str, _egress_iface: str) -> None:
    if protocol not in _PROTOCOL_TABLE:
        raise ValueError(f"Unknown protocol: {protocol!r}")
    table = _PROTOCOL_TABLE[protocol]
    iface = _PROTOCOL_IFACE[protocol]

    # Remove only this protocol's rule(s).
    for _ in range(4):
        if not _run("ip", "rule", "del", "iif", iface, "table", str(table)):
            break

    # Remove only this protocol's route-table entries.
    _run("ip", "-4", "route", "flush", "table", str(table))
