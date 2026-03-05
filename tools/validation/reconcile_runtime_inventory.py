#!/usr/bin/env python3
"""
Normalize the current runtime VPN inventory to the host we are validating.

This is intended for single-host/local validation and for the remote bootstrap
wrapper after it restarts the backend against the repo's local SQLite runtime.
"""

from __future__ import annotations

import ipaddress
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from database.session import SessionLocal
from models.vpn_server import VPNServer
from services.server_bootstrap import ensure_default_servers


def _stdout(cmd: list[str]) -> str:
    try:
        result = subprocess.run(
            cmd,
            check=True,
            text=True,
            capture_output=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""
    return result.stdout.strip()


def _detect_public_ip() -> str:
    raw = _stdout(["hostname", "-I"])
    ips = [part for part in raw.split() if part]

    for candidate in ips:
        try:
            ip = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if isinstance(ip, ipaddress.IPv4Address) and not (
            ip.is_loopback or ip.is_private or ip.is_link_local
        ):
            return candidate

    if ips:
        return ips[0]

    route = _stdout(["ip", "-4", "route", "get", "1.1.1.1"])
    fields = route.split()
    for idx, field in enumerate(fields[:-1]):
        if field == "src":
            return fields[idx + 1]

    raise SystemExit("Unable to detect a usable host IP.")


def _read_first(paths: list[Path]) -> str | None:
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if text:
            return text
    return None


def _wireguard_public_key() -> str | None:
    key = _stdout(["wg", "show", "wg0", "public-key"])
    if key:
        return key
    return _read_first(
        [
            Path("/etc/wireguard/public.key"),
            Path("/etc/securewave/wireguard/public.key"),
        ]
    )


def _openvpn_settings(host_ip: str) -> tuple[bool, str | None, int | None, str | None, str | None]:
    conf_path = Path("/etc/openvpn/server/server.conf")
    ca_pem = _read_first([Path("/etc/openvpn/server/ca.crt")])
    if not conf_path.exists() or not ca_pem:
        return False, None, None, None, None

    port = 1194
    proto = "udp"
    try:
        for line in conf_path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith(";"):
                continue
            parts = stripped.split()
            if len(parts) < 2:
                continue
            if parts[0] == "port":
                try:
                    port = int(parts[1])
                except ValueError:
                    pass
            elif parts[0] == "proto":
                proto = parts[1].lower()
    except OSError:
        return False, None, None, None, None

    return True, host_ip, port, proto, ca_pem


def _ikev2_settings(host_ip: str) -> tuple[bool, str | None, str | None]:
    ca_pem = _read_first(
        [
            Path("/etc/ipsec.d/cacerts/securewave-ikev2-ca-cert.pem"),
            Path("/etc/ipsec.d/cacerts/ca-cert.pem"),
        ]
    )
    if not ca_pem:
        return False, None, None

    remote_id = host_ip
    conf_path = Path("/etc/ipsec.conf")
    try:
        for line in conf_path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("leftid="):
                value = stripped.split("=", 1)[1].strip()
                if value:
                    remote_id = value
                    break
    except OSError:
        pass

    return True, remote_id, ca_pem


def main() -> int:
    host_ip = _detect_public_ip()
    wg_key = _wireguard_public_key()
    ovpn_enabled, ovpn_host, ovpn_port, ovpn_proto, ovpn_ca = _openvpn_settings(host_ip)
    ike_enabled, ike_remote_id, ike_ca = _ikev2_settings(host_ip)

    session = SessionLocal()
    try:
        ensure_default_servers(session)
        servers = session.query(VPNServer).all()
        if not servers:
            raise SystemExit("No vpn_servers rows exist after bootstrap.")

        for server in servers:
            server.status = "active"
            server.health_status = "healthy"
            server.hcloud_server_state = "running"
            server.public_ip = host_ip
            server.endpoint = f"{host_ip}:51820"
            server.wg_listen_port = 51820
            server.supports_wireguard = True
            server.protocol = "wireguard"

            if wg_key:
                server.wg_public_key = wg_key

            if ovpn_enabled:
                server.supports_openvpn = True
                server.openvpn_endpoint = ovpn_host
                server.openvpn_port = ovpn_port
                server.openvpn_transport = ovpn_proto
                server.openvpn_ca_cert_pem = ovpn_ca
            else:
                server.supports_openvpn = False

            if ike_enabled:
                server.supports_ikev2 = True
                server.ikev2_remote_id = ike_remote_id
                server.ikev2_ca_cert_pem = ike_ca
            else:
                server.supports_ikev2 = False

            session.add(server)

        session.commit()
        print(
            "Reconciled runtime inventory:",
            f"rows={len(servers)}",
            f"host_ip={host_ip}",
            f"wireguard_key={'yes' if bool(wg_key) else 'no'}",
            f"openvpn={'yes' if ovpn_enabled else 'no'}",
            f"ikev2={'yes' if ike_enabled else 'no'}",
        )
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    raise SystemExit(main())
