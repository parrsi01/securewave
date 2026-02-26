#!/usr/bin/env python3
"""
Audit and reconcile SecureWave VPN fleet state against Hetzner Cloud.

What this script does:
1) Enumerates active Hetzner servers via API
2) Extracts region/location/public/private IPs + reverse DNS
3) Validates attached firewalls and required ingress ports
4) Optionally SSH-checks protocol/routing state on each server
5) Optionally compares the live fleet to backend vpn_servers rows

Production usage (Ubuntu 22.04 / Hetzner):
  export HETZNER_API_TOKEN=...
  python infrastructure/hetzner/audit_vpn_fleet.py --json-out /tmp/securewave_fleet_audit.json

Add SSH checks (recommended):
  python infrastructure/hetzner/audit_vpn_fleet.py \\
    --ssh-checks --ssh-user root --ssh-key-path ~/.ssh/securewave_prod \\
    --json-out /tmp/securewave_fleet_audit.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess  # nosec B404 - operator-controlled commands
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx


HCLOUD_API_BASE = "https://api.hetzner.cloud/v1"
WG_DEFAULT_PORT = 51820
OPENVPN_DEFAULT_PORT = 1194
IKEV2_UDP_PORTS = (500, 4500)


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _hcloud_get(token: str, path: str, *, params: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    headers = {"Authorization": f"Bearer {token}"}
    with httpx.Client(timeout=20) as client:
        resp = client.get(f"{HCLOUD_API_BASE}{path}", headers=headers, params=params)
        resp.raise_for_status()
        return resp.json()


def _hcloud_paginated(token: str, path: str, key: str) -> list[dict[str, Any]]:
    page = 1
    out: list[dict[str, Any]] = []
    while True:
        payload = _hcloud_get(token, path, params={"page": page, "per_page": 50})
        items = payload.get(key) or []
        if not isinstance(items, list):
            raise RuntimeError(f"Unexpected Hetzner API payload for {path}: '{key}' is not a list")
        out.extend([item for item in items if isinstance(item, dict)])
        pagination = payload.get("meta", {}).get("pagination", {})
        next_page = pagination.get("next_page")
        if not next_page:
            break
        page = int(next_page)
    return out


def _rdns_values(server: dict[str, Any]) -> dict[str, Any]:
    public_net = server.get("public_net") or {}
    ipv4 = (public_net.get("ipv4") or {}) if isinstance(public_net, dict) else {}
    ipv6 = (public_net.get("ipv6") or {}) if isinstance(public_net, dict) else {}
    ipv4_ptr = str(ipv4.get("dns_ptr") or "").strip() or None

    ipv6_ptrs: list[str] = []
    raw_ipv6_ptr = ipv6.get("dns_ptr")
    if isinstance(raw_ipv6_ptr, list):
        for item in raw_ipv6_ptr:
            if isinstance(item, dict):
                ptr = str(item.get("dns_ptr") or "").strip()
                if ptr:
                    ipv6_ptrs.append(ptr)
            else:
                ptr = str(item or "").strip()
                if ptr:
                    ipv6_ptrs.append(ptr)
    elif raw_ipv6_ptr:
        ptr = str(raw_ipv6_ptr).strip()
        if ptr:
            ipv6_ptrs.append(ptr)

    return {
        "ipv4_ptr": ipv4_ptr,
        "ipv4_ptr_present": bool(ipv4_ptr),
        "ipv6_ptrs": ipv6_ptrs,
        "ipv6_ptr_present": len(ipv6_ptrs) > 0,
    }


def _extract_private_ips(server: dict[str, Any]) -> list[str]:
    out: list[str] = []
    for item in server.get("private_net") or []:
        if not isinstance(item, dict):
            continue
        ip = str(item.get("ip") or "").strip()
        if ip:
            out.append(ip)
    return out


def _extract_public_ipv4(server: dict[str, Any]) -> Optional[str]:
    public_net = server.get("public_net") or {}
    ipv4 = (public_net.get("ipv4") or {}) if isinstance(public_net, dict) else {}
    ip = str(ipv4.get("ip") or "").strip()
    return ip or None


def _extract_public_ipv6(server: dict[str, Any]) -> Optional[str]:
    public_net = server.get("public_net") or {}
    ipv6 = (public_net.get("ipv6") or {}) if isinstance(public_net, dict) else {}
    ip = str(ipv6.get("ip") or "").strip()
    return ip or None


def _server_location_info(server: dict[str, Any]) -> dict[str, Any]:
    dc = server.get("datacenter") or {}
    loc = dc.get("location") or {}
    city = str(loc.get("city") or "").strip()
    country = str(loc.get("country") or "").strip().upper()
    code = str(loc.get("name") or "").strip().lower()

    region = "Other"
    if country in {"US", "CA", "MX", "BB"}:
        region = "Americas"
    elif country in {"DE", "NL", "GB", "FR", "FI", "SE", "NO", "PL", "ES", "IT", "IE", "CH", "AT", "PT", "RO"}:
        region = "Europe"
    elif country in {"SG", "JP", "AU", "NZ", "KR", "IN", "TW", "HK"}:
        region = "Asia-Pacific"
    elif country in {"AE", "IL", "TR", "ZA"}:
        region = "Middle East & Africa"

    return {
        "hcloud_location": code or None,
        "city": city or None,
        "country_code": country or None,
        "region": region,
    }


def _barbados_priority(name: str, server_id: str, city: str, hcloud_location: str, country_code: str, region: str) -> int:
    tags = " ".join(
        part for part in [name, server_id, city, hcloud_location] if part
    ).lower()
    if "ash" in tags or "ashburn" in tags:
        return 10
    if "mia" in tags or "miami" in tags:
        return 20
    if "yul" in tags or "ymq" in tags or "montreal" in tags or "montréal" in tags:
        return 30
    if "frankfurt" in tags:
        return 100
    if country_code == "DE" or hcloud_location in {"fsn1", "nbg1"}:
        return 110
    if region == "Americas":
        return 150
    if region == "Europe":
        return 200
    if region == "Asia-Pacific":
        return 300
    if region == "Middle East & Africa":
        return 320
    return 400


def _firewall_rule_port_allows(rule: dict[str, Any], *, protocol: str, port: int) -> bool:
    if str(rule.get("direction") or "").lower() != "in":
        return False
    if str(rule.get("protocol") or "").lower() != protocol.lower():
        return False
    port_text = str(rule.get("port") or "").strip()
    if not port_text:
        return False
    if port_text == str(port):
        return True
    if "-" in port_text:
        try:
            start_s, end_s = port_text.split("-", 1)
            return int(start_s) <= port <= int(end_s)
        except ValueError:
            return False
    if "," in port_text:
        return any(part.strip() == str(port) for part in port_text.split(","))
    return False


def _server_attached_firewall_ids(server: dict[str, Any], firewalls: list[dict[str, Any]]) -> list[int]:
    # Prefer the server payload if present.
    attached = server.get("firewalls")
    if isinstance(attached, list):
        ids = []
        for item in attached:
            if isinstance(item, dict):
                fw_id = item.get("id")
                if isinstance(fw_id, int):
                    ids.append(fw_id)
        if ids:
            return sorted(set(ids))

    # Fallback: derive from firewall.applied_to
    server_id = server.get("id")
    if not isinstance(server_id, int):
        return []
    out: list[int] = []
    for fw in firewalls:
        fw_id = fw.get("id")
        if not isinstance(fw_id, int):
            continue
        for target in fw.get("applied_to") or []:
            if not isinstance(target, dict):
                continue
            if str(target.get("type") or "").lower() != "server":
                continue
            target_server = target.get("server")
            target_server_id: Optional[int] = None
            if isinstance(target_server, int):
                target_server_id = target_server
            elif isinstance(target_server, dict):
                nested_id = target_server.get("id")
                if isinstance(nested_id, int):
                    target_server_id = nested_id
            if target_server_id == server_id:
                out.append(fw_id)
                break
    return sorted(set(out))


def _firewall_validation(server: dict[str, Any], firewalls: list[dict[str, Any]], *, wg_port: int, openvpn_port: int) -> dict[str, Any]:
    attached_ids = _server_attached_firewall_ids(server, firewalls)
    fw_by_id = {fw["id"]: fw for fw in firewalls if isinstance(fw.get("id"), int)}
    attached_rules = [rule for fw_id in attached_ids for rule in (fw_by_id.get(fw_id, {}).get("rules") or []) if isinstance(rule, dict)]

    wg_allowed = any(_firewall_rule_port_allows(rule, protocol="udp", port=wg_port) for rule in attached_rules)
    openvpn_udp_allowed = any(_firewall_rule_port_allows(rule, protocol="udp", port=openvpn_port) for rule in attached_rules)
    openvpn_tcp_allowed = any(_firewall_rule_port_allows(rule, protocol="tcp", port=openvpn_port) for rule in attached_rules)
    ikev2_500_allowed = any(_firewall_rule_port_allows(rule, protocol="udp", port=500) for rule in attached_rules)
    ikev2_4500_allowed = any(_firewall_rule_port_allows(rule, protocol="udp", port=4500) for rule in attached_rules)

    return {
        "attached_firewall_ids": attached_ids,
        "attached_firewall_names": [
            str((fw_by_id.get(fw_id) or {}).get("name") or fw_id)
            for fw_id in attached_ids
        ],
        "validation": {
            "has_firewall": len(attached_ids) > 0,
            "wireguard_udp_port_allowed": wg_allowed,
            "openvpn_udp_port_allowed": openvpn_udp_allowed,
            "openvpn_tcp_port_allowed": openvpn_tcp_allowed,
            "ikev2_udp_500_allowed": ikev2_500_allowed,
            "ikev2_udp_4500_allowed": ikev2_4500_allowed,
        },
    }


def _ssh_run(
    host: str,
    remote_cmd: str,
    *,
    ssh_user: str,
    ssh_key_path: Optional[Path],
    ssh_port: int,
    timeout_s: int,
) -> tuple[bool, str]:
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=6",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-p",
        str(ssh_port),
    ]
    if ssh_key_path:
        cmd.extend(["-i", str(ssh_key_path)])
    cmd.append(f"{ssh_user}@{host}")
    cmd.append(remote_cmd)
    try:
        proc = subprocess.run(  # nosec B603
            cmd,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_s,
        )
    except (subprocess.SubprocessError, OSError, TimeoutError) as exc:
        return False, str(exc)
    output = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    if proc.returncode != 0:
        return False, err or output or f"ssh exited {proc.returncode}"
    return True, output


def _ssh_bool(host: str, cmd: str, **kwargs: Any) -> Optional[bool]:
    ok, out = _ssh_run(host, cmd, **kwargs)
    if not ok:
        return None
    text = out.strip().lower()
    if text in {"1", "true", "yes"}:
        return True
    if text in {"0", "false", "no"}:
        return False
    return None


def _parse_ss_ports(text: str) -> set[int]:
    ports: set[int] = set()
    for line in text.splitlines():
        for match in re.finditer(r":(\d+)\b", line):
            try:
                ports.add(int(match.group(1)))
            except ValueError:
                continue
    return ports


def _ssh_protocol_and_routing_checks(
    host: str,
    *,
    ssh_user: str,
    ssh_key_path: Optional[Path],
    ssh_port: int,
    timeout_s: int,
    wg_port: int,
    openvpn_port: int,
) -> dict[str, Any]:
    kwargs = {
        "ssh_user": ssh_user,
        "ssh_key_path": ssh_key_path,
        "ssh_port": ssh_port,
        "timeout_s": timeout_s,
    }

    def run(cmd: str) -> tuple[bool, str]:
        return _ssh_run(host, cmd, **kwargs)

    sudo = "sudo -n "
    wg_bin = _ssh_bool(host, "bash -lc 'command -v wg >/dev/null && command -v wg-quick >/dev/null && echo 1 || echo 0'", **kwargs)
    ovpn_bin = _ssh_bool(host, "bash -lc 'command -v openvpn >/dev/null && echo 1 || echo 0'", **kwargs)
    ike_bin = _ssh_bool(host, "bash -lc '(command -v swanctl >/dev/null || command -v ipsec >/dev/null) && echo 1 || echo 0'", **kwargs)

    ok, ss_udp = run(f"bash -lc '{sudo}ss -H -lunp 2>/dev/null || ss -H -lunp 2>/dev/null || true'")
    ok2, ss_tcp = run(f"bash -lc '{sudo}ss -H -ltnp 2>/dev/null || ss -H -ltnp 2>/dev/null || true'")
    udp_ports = _parse_ss_ports(ss_udp if ok else "")
    tcp_ports = _parse_ss_ports(ss_tcp if ok2 else "")

    def _svc(*names: str) -> Optional[str]:
        for name in names:
            ok_svc, out_svc = run(f"bash -lc '{sudo}systemctl is-active {name} 2>/dev/null || true'")
            if ok_svc:
                state = (out_svc or "").strip()
                if state:
                    return state
        return None

    wg_service = _svc("wg-quick@wg0")
    openvpn_service = _svc("openvpn-server@server", "openvpn@server", "openvpn")
    ikev2_service = _svc("strongswan-starter", "strongswan", "charon-systemd")

    wg_conf = _ssh_bool(host, "bash -lc '[ -f /etc/wireguard/wg0.conf ] && echo 1 || echo 0'", **kwargs)
    ovpn_conf = _ssh_bool(
        host,
        "bash -lc 'if [ -f /etc/openvpn/server/server.conf ] || [ -f /etc/openvpn/server.conf ]; then echo 1; else echo 0; fi'",
        **kwargs,
    )
    ikev2_conf = _ssh_bool(
        host,
        "bash -lc 'if [ -f /etc/ipsec.conf ] || [ -f /etc/swanctl/swanctl.conf ]; then echo 1; else echo 0; fi'",
        **kwargs,
    )

    ok, ovpn_certs_text = run(
        "bash -lc '"
        "c1=/etc/openvpn/server/ca.crt; c2=/etc/openvpn/ca.crt; "
        "s1=/etc/openvpn/server/server.crt; s2=/etc/openvpn/server.crt; "
        "k1=/etc/openvpn/server/server.key; k2=/etc/openvpn/server.key; "
        "([ -f \"$c1\" ] || [ -f \"$c2\" ]) && ([ -f \"$s1\" ] || [ -f \"$s2\" ]) && ([ -f \"$k1\" ] || [ -f \"$k2\" ]) && echo 1 || echo 0'"
    )
    ovpn_certs = (ovpn_certs_text.strip() == "1") if ok else None

    ok, ikev2_certs_text = run(
        "bash -lc '"
        "([ -f /etc/ipsec.d/cacerts/ca-cert.pem ] || [ -d /etc/ipsec.d/cacerts ]) && "
        "([ -f /etc/ipsec.d/certs/server-cert.pem ] || [ -d /etc/ipsec.d/certs ]) && echo 1 || echo 0'"
    )
    ikev2_certs = (ikev2_certs_text.strip() == "1") if ok else None

    ok, ip_forward_out = run(f"bash -lc '{sudo}sysctl -n net.ipv4.ip_forward 2>/dev/null || sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0'")
    ip_forward = (ip_forward_out.strip() == "1") if ok else None

    _, default_route = run("bash -lc 'ip route show default 2>/dev/null || true'")
    _, nat_rules = run(f"bash -lc '{sudo}iptables -t nat -S POSTROUTING 2>/dev/null || iptables -t nat -S POSTROUTING 2>/dev/null || true'")
    _, wg_hooks = run("bash -lc 'grep -E \"^(PostUp|PostDown)\\s*=\" /etc/wireguard/wg0.conf 2>/dev/null || true'")
    docker_present = _ssh_bool(host, "bash -lc 'ip link show docker0 >/dev/null 2>&1 && echo 1 || echo 0'", **kwargs)

    nat_has_eth0_masq = any("MASQUERADE" in line and ("-o eth0" in line or "-o ens" in line) for line in nat_rules.splitlines())
    wg_hooks_has_nat = "MASQUERADE" in wg_hooks

    return {
        "wireguard": {
            "binary_present": wg_bin,
            "service_status": wg_service,
            "port_bound": wg_port in udp_ports,
            "config_present": wg_conf,
            "postup_postdown_present": bool(wg_hooks.strip()),
            "postup_postdown_has_nat": wg_hooks_has_nat,
        },
        "openvpn": {
            "binary_present": ovpn_bin,
            "service_status": openvpn_service,
            "port_bound_udp": openvpn_port in udp_ports,
            "port_bound_tcp": openvpn_port in tcp_ports,
            "config_present": ovpn_conf,
            "certs_present": ovpn_certs,
        },
        "ikev2": {
            "binary_present": ike_bin,
            "service_status": ikev2_service,
            "port_bound_udp_500": 500 in udp_ports,
            "port_bound_udp_4500": 4500 in udp_ports,
            "config_present": ikev2_conf,
            "certs_present": ikev2_certs,
        },
        "routing": {
            "default_route": default_route.splitlines(),
            "ip_forward_enabled": ip_forward,
            "nat_postrouting_rules": nat_rules.splitlines(),
            "wg0_postup_postdown_lines": wg_hooks.splitlines(),
            "docker_bridge_present": docker_present,
            "nat_has_primary_masquerade": nat_has_eth0_masq,
        },
    }


def _load_backend_registry_snapshot(project_root: Path) -> dict[str, Any]:
    """
    Optional local comparison against backend vpn_servers table.
    """
    sys.path.insert(0, str(project_root))
    try:
        from database.session import SessionLocal  # type: ignore
        from models.vpn_server import VPNServer  # type: ignore
    except Exception as exc:
        return {"available": False, "error": f"backend import failed: {exc}"}

    db = SessionLocal()
    try:
        rows = db.query(VPNServer).all()
        snapshot = []
        for row in rows:
            snapshot.append(
                {
                    "server_id": str(row.server_id),
                    "hcloud_server_id": str(row.hcloud_server_id) if row.hcloud_server_id else None,
                    "hcloud_server_name": str(row.hcloud_server_name) if row.hcloud_server_name else None,
                    "public_ip": str(row.public_ip) if row.public_ip else None,
                    "private_ip": str(row.private_ip) if row.private_ip else None,
                    "region": str(row.region) if row.region else None,
                    "status": str(row.status),
                    "health_status": str(row.health_status),
                    "supports_wireguard": bool(getattr(row, "supports_wireguard", True)),
                    "supports_openvpn": bool(getattr(row, "supports_openvpn", False)),
                    "supports_ikev2": bool(getattr(row, "supports_ikev2", False)),
                }
            )
        return {"available": True, "rows": snapshot}
    finally:
        db.close()


def _compare_backend_registry(servers: list[dict[str, Any]], backend_snapshot: dict[str, Any]) -> dict[str, Any]:
    if not backend_snapshot.get("available"):
        return backend_snapshot

    backend_rows = backend_snapshot.get("rows") or []
    by_hcloud_id = {}
    by_server_id = {}
    for row in backend_rows:
        if row.get("hcloud_server_id"):
            by_hcloud_id[str(row["hcloud_server_id"])] = row
        by_server_id[str(row.get("server_id") or "")] = row

    missing_in_backend: list[str] = []
    ip_mismatches: list[dict[str, Any]] = []
    region_mismatches: list[dict[str, Any]] = []
    matched_backend_ids: set[str] = set()

    for server in servers:
        live_id = str(server.get("id"))
        live_name = str(server.get("name") or "")
        live_ipv4 = str(server.get("public_ipv4") or "")
        live_region = str(server.get("region") or "")
        row = by_hcloud_id.get(live_id) or by_server_id.get(live_name)
        if not row:
            missing_in_backend.append(live_name or live_id)
            continue
        matched_backend_ids.add(str(row.get("server_id") or ""))
        backend_ip = str(row.get("public_ip") or "")
        backend_region = str(row.get("region") or "")
        if live_ipv4 and backend_ip and live_ipv4 != backend_ip:
            ip_mismatches.append({"server": live_name, "live_public_ip": live_ipv4, "backend_public_ip": backend_ip})
        if live_region and backend_region and live_region != backend_region:
            region_mismatches.append({"server": live_name, "live_region": live_region, "backend_region": backend_region})

    stale_backend_rows = [
        row.get("server_id")
        for row in backend_rows
        if str(row.get("server_id") or "") not in matched_backend_ids and str(row.get("status") or "").lower() == "active"
    ]

    return {
        "available": True,
        "backend_total": len(backend_rows),
        "missing_in_backend": sorted(missing_in_backend),
        "stale_backend_active_rows": sorted([str(x) for x in stale_backend_rows if x]),
        "ip_mismatches": ip_mismatches,
        "region_mismatches": region_mismatches,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit SecureWave Hetzner VPN fleet and backend registry")
    parser.add_argument("--json-out", default="", help="Write full JSON report to this file")
    parser.add_argument("--only-running", action="store_true", help="Only include servers with Hetzner status=running")
    parser.add_argument("--name-prefix", default="", help="Only include servers whose name starts with this prefix")
    parser.add_argument("--wg-port", type=int, default=WG_DEFAULT_PORT)
    parser.add_argument("--openvpn-port", type=int, default=OPENVPN_DEFAULT_PORT)
    parser.add_argument("--ssh-checks", action="store_true", help="Run SSH protocol/routing checks on each server")
    parser.add_argument("--ssh-user", default=os.getenv("WG_SSH_USER", "root"))
    parser.add_argument("--ssh-key-path", default=os.getenv("WG_SSH_KEY_PATH", ""))
    parser.add_argument("--ssh-port", type=int, default=22)
    parser.add_argument("--ssh-timeout", type=int, default=12)
    parser.add_argument("--compare-backend-db", action="store_true", help="Compare against local backend vpn_servers rows")
    parser.add_argument(
        "--project-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="Project root for backend DB imports when using --compare-backend-db",
    )
    args = parser.parse_args()

    token = os.getenv("HETZNER_API_TOKEN", "").strip()
    if not token:
        raise SystemExit("HETZNER_API_TOKEN must be set")

    ssh_key_path = Path(args.ssh_key_path).expanduser().resolve() if args.ssh_key_path else None
    if args.ssh_checks and args.ssh_key_path and not ssh_key_path.exists():
        raise SystemExit(f"SSH key not found: {ssh_key_path}")

    servers_raw = _hcloud_paginated(token, "/servers", "servers")
    firewalls = _hcloud_paginated(token, "/firewalls", "firewalls")

    fleet: list[dict[str, Any]] = []
    for server in servers_raw:
        status = str(server.get("status") or "").strip().lower()
        if args.only_running and status != "running":
            continue
        name = str(server.get("name") or "").strip()
        if args.name_prefix and not name.startswith(args.name_prefix):
            continue

        loc = _server_location_info(server)
        public_ipv4 = _extract_public_ipv4(server)
        public_ipv6 = _extract_public_ipv6(server)
        private_ips = _extract_private_ips(server)
        rdns = _rdns_values(server)
        fw = _firewall_validation(
            server,
            firewalls,
            wg_port=args.wg_port,
            openvpn_port=args.openvpn_port,
        )
        priority = _barbados_priority(
            name=name,
            server_id=str(server.get("id") or ""),
            city=str(loc.get("city") or ""),
            hcloud_location=str(loc.get("hcloud_location") or ""),
            country_code=str(loc.get("country_code") or ""),
            region=str(loc.get("region") or "Other"),
        )

        row: dict[str, Any] = {
            "id": server.get("id"),
            "name": name,
            "status": status,
            "public_ipv4": public_ipv4,
            "public_ipv6": public_ipv6,
            "private_ips": private_ips,
            "rdns": rdns,
            "region": loc.get("region"),
            "city": loc.get("city"),
            "country_code": loc.get("country_code"),
            "hcloud_location": loc.get("hcloud_location"),
            "latency_priority": priority,
            "firewall": fw,
            "validation": {
                "has_public_ipv4": bool(public_ipv4),
                "has_private_network": len(private_ips) > 0,
                "reverse_dns_ipv4_present": bool(rdns.get("ipv4_ptr_present")),
                "firewall_attached": bool(fw["validation"]["has_firewall"]),
            },
        }

        if args.ssh_checks and public_ipv4:
            try:
                row["host_checks"] = _ssh_protocol_and_routing_checks(
                    public_ipv4,
                    ssh_user=args.ssh_user,
                    ssh_key_path=ssh_key_path,
                    ssh_port=args.ssh_port,
                    timeout_s=args.ssh_timeout,
                    wg_port=args.wg_port,
                    openvpn_port=args.openvpn_port,
                )
            except Exception as exc:
                row["host_checks_error"] = str(exc)

        fleet.append(row)

    fleet.sort(
        key=lambda r: (
            int(r.get("latency_priority") or 9999),
            0 if str(r.get("status") or "") == "running" else 1,
            str(r.get("name") or "").lower(),
        )
    )

    backend_compare = None
    if args.compare_backend_db:
        project_root = Path(args.project_root).resolve()
        backend_snapshot = _load_backend_registry_snapshot(project_root)
        backend_compare = _compare_backend_registry(fleet, backend_snapshot)

    report = {
        "generated_at": _utcnow_iso(),
        "filters": {
            "only_running": bool(args.only_running),
            "name_prefix": args.name_prefix or None,
        },
        "barbados_routing_priority_order": [
            "10: US East / Ashburn",
            "20: Miami (if available)",
            "30: Montreal (if available)",
            "100+: Germany/Frankfurt-class fallback",
        ],
        "totals": {
            "servers": len(fleet),
            "running": sum(1 for row in fleet if row.get("status") == "running"),
            "with_private_network": sum(1 for row in fleet if row.get("validation", {}).get("has_private_network")),
            "with_reverse_dns_ipv4": sum(1 for row in fleet if row.get("validation", {}).get("reverse_dns_ipv4_present")),
            "with_firewall": sum(1 for row in fleet if row.get("validation", {}).get("firewall_attached")),
        },
        "servers": fleet,
        "backend_registry_compare": backend_compare,
    }

    if args.json_out:
        out_path = Path(args.json_out).expanduser().resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(report, indent=2, sort_keys=False) + "\n", encoding="utf-8")

    print(f"SecureWave Hetzner Fleet Audit @ {report['generated_at']}")
    print(f"Servers: total={report['totals']['servers']} running={report['totals']['running']}")
    for row in fleet:
        fw_ok = row["validation"]["firewall_attached"]
        rdns_ok = row["validation"]["reverse_dns_ipv4_present"]
        priv_ok = row["validation"]["has_private_network"]
        print(
            f"- prio={row['latency_priority']:>3} {row['name']} "
            f"[{row.get('hcloud_location') or '-'} {row.get('city') or '-'} {row.get('country_code') or '-'}] "
            f"ipv4={row.get('public_ipv4') or '-'} private={len(row.get('private_ips') or [])} "
            f"fw={'ok' if fw_ok else 'missing'} rdns={'ok' if rdns_ok else 'missing'} "
            f"status={row.get('status')}"
        )

    if backend_compare and backend_compare.get("available"):
        print(
            "Backend registry compare:"
            f" missing_in_backend={len(backend_compare.get('missing_in_backend') or [])}"
            f" stale_backend_active_rows={len(backend_compare.get('stale_backend_active_rows') or [])}"
            f" ip_mismatches={len(backend_compare.get('ip_mismatches') or [])}"
            f" region_mismatches={len(backend_compare.get('region_mismatches') or [])}"
        )
    elif backend_compare:
        print(f"Backend registry compare unavailable: {backend_compare.get('error')}")

    if args.json_out:
        print(f"JSON report: {args.json_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
