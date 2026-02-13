"""
Adaptive WireGuard tuning helpers.
"""

from __future__ import annotations

import ipaddress
import os
import shutil
import socket
import subprocess  # nosec B404 - controlled local probe
import time
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class WireGuardTuning:
    mtu: Optional[int]
    keepalive_seconds: int
    nat_detected: bool
    mtu_probe_ms: float


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        return int(raw)
    except ValueError:
        return default


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def detect_nat(client_ip: Optional[str], forwarded_for: Optional[str], device_type: Optional[str] = None) -> bool:
    if forwarded_for:
        parts = [p.strip() for p in forwarded_for.split(",") if p.strip()]
        if len(parts) > 1:
            return True

    if client_ip:
        try:
            ip = ipaddress.ip_address(client_ip)
            if ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_link_local:
                return True
            # Carrier grade NAT range.
            if ip.version == 4 and ip in ipaddress.ip_network("100.64.0.0/10"):
                return True
        except ValueError:
            pass

    if (device_type or "").lower().strip() in {"ios", "android"}:
        # Mobile clients are often behind NATs and benefit from keepalive.
        return True
    return False


def _probe_mtu(host: str, candidates: list[int]) -> tuple[Optional[int], float]:
    ping_path = shutil.which("ping")
    if not ping_path:
        return None, 0.0

    start = time.monotonic()
    for mtu in candidates:
        payload_size = max(0, mtu - 28)  # IPv4 header + ICMP
        cmd = [
            ping_path,
            "-c",
            "1",
            "-W",
            "1",
            "-M",
            "do",
            "-s",
            str(payload_size),
            host,
        ]
        try:
            proc = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=2)  # nosec B603
        except (subprocess.SubprocessError, OSError, TimeoutError):
            continue
        if proc.returncode == 0:
            return mtu, (time.monotonic() - start) * 1000

    return None, (time.monotonic() - start) * 1000


def _host_from_endpoint(endpoint: str) -> str:
    endpoint = endpoint.strip()
    if endpoint.startswith("[") and "]" in endpoint:
        return endpoint[1:].split("]", 1)[0]
    if endpoint.count(":") == 1:
        return endpoint.split(":", 1)[0]
    # Fall back to plain host for uncommon endpoint format.
    return endpoint


def _is_ipv6_host(host: str) -> bool:
    try:
        info = socket.getaddrinfo(host, None)
    except OSError:
        return ":" in host
    for entry in info:
        if entry[0] == socket.AF_INET6:
            return True
    return False


def tune_wireguard(
    *,
    endpoint: str,
    client_ip: Optional[str],
    forwarded_for: Optional[str],
    observed_latency_ms: Optional[float],
    device_type: Optional[str],
) -> WireGuardTuning:
    """
    Compute adaptive MTU and keepalive values.

    - MTU probing is best-effort and disabled with `SECUREWAVE_MTU_PROBE=false`.
    - Keepalive increases when NAT is detected.
    """
    nat_detected = detect_nat(client_ip, forwarded_for, device_type=device_type)

    forced_mtu_raw = os.getenv("SECUREWAVE_WG_MTU", "").strip()
    forced_mtu: Optional[int] = None
    if forced_mtu_raw:
        try:
            parsed = int(forced_mtu_raw)
            if 1200 <= parsed <= 1500:
                forced_mtu = parsed
        except ValueError:
            forced_mtu = None

    mtu_probe_ms = 0.0
    mtu = forced_mtu
    if mtu is None:
        host = _host_from_endpoint(endpoint)
        probe_enabled = _bool_env("SECUREWAVE_MTU_PROBE", True)
        if probe_enabled:
            candidate_mtu = [1420, 1400, 1380, 1360, 1320, 1280]
            mtu, mtu_probe_ms = _probe_mtu(host, candidate_mtu)

        if mtu is None:
            # Heuristic fallback by observed conditions.
            if _is_ipv6_host(host):
                mtu = 1280
            elif observed_latency_ms and observed_latency_ms > 220:
                mtu = 1360
            elif nat_detected:
                mtu = 1380
            else:
                mtu = 1420

    keepalive_nat = _int_env("SECUREWAVE_WG_KEEPALIVE_NAT", 25)
    keepalive_public = _int_env("SECUREWAVE_WG_KEEPALIVE_PUBLIC", 15)
    keepalive_seconds = keepalive_nat if nat_detected else keepalive_public
    keepalive_seconds = max(0, min(keepalive_seconds, 600))

    return WireGuardTuning(
        mtu=mtu,
        keepalive_seconds=keepalive_seconds,
        nat_detected=nat_detected,
        mtu_probe_ms=round(mtu_probe_ms, 2),
    )
