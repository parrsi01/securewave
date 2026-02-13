#!/usr/bin/env python3
"""
Sync Hetzner Cloud servers into the SecureWave VPN server registry (database).

This script does NOT provision infrastructure. It only registers already-
provisioned WireGuard servers so the backend can issue real profiles.

Inputs (best-effort, in this order):
1) Terraform outputs from infrastructure/hetzner (server_ids, names, ipv4)
2) Hetzner Cloud API (location, server_type, state) via HETZNER_API_TOKEN
3) WireGuard public key fetched from the server over SSH (recommended)

Security notes:
- Server *private* keys are not pulled into the backend.
- Client keys remain encrypted at rest in the backend (WG_ENCRYPTION_KEY).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess  # nosec B404 - controlled subprocess usage
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import httpx


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from database.session import SessionLocal  # noqa: E402
from models.vpn_server import VPNServer  # noqa: E402


HCLOUD_API_BASE = "https://api.hetzner.cloud/v1"
DEFAULT_WG_PORT = 51820
_WG_PUB_RE = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")


@dataclass(frozen=True)
class TerraformOutputs:
    server_ids: list[str]
    server_names: list[str]
    server_ipv4: list[str]


def _run(cmd: list[str], *, cwd: Optional[Path] = None) -> str:
    return subprocess.check_output(cmd, cwd=str(cwd) if cwd else None).decode("utf-8").strip()  # nosec B603


def _read_terraform_outputs(terraform_dir: Path) -> TerraformOutputs:
    raw = _run(["terraform", "output", "-json"], cwd=terraform_dir)
    data = json.loads(raw)

    def _values(key: str) -> list[str]:
        output = data.get(key) or {}
        value = output.get("value")
        if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
            raise ValueError(f"terraform output '{key}' missing or not a string list")
        return value

    server_ids = _values("server_ids")
    server_names = _values("server_names")
    server_ipv4 = _values("server_ipv4")

    if not (len(server_ids) == len(server_names) == len(server_ipv4)):
        raise ValueError("terraform outputs have mismatched list lengths")

    return TerraformOutputs(server_ids=server_ids, server_names=server_names, server_ipv4=server_ipv4)


def _hcloud_get(token: str, path: str) -> dict[str, Any]:
    url = f"{HCLOUD_API_BASE}{path}"
    headers = {"Authorization": f"Bearer {token}"}
    with httpx.Client(timeout=20) as client:
        resp = client.get(url, headers=headers)
        resp.raise_for_status()
        return resp.json()


def _fetch_wg_public_key_over_ssh(
    public_ip: str,
    *,
    ssh_user: str,
    ssh_key_path: Path,
    ssh_port: int = 22,
) -> str:
    if not ssh_key_path.exists():
        raise FileNotFoundError(f"SSH key not found: {ssh_key_path}")

    cmd = [
        "ssh",
        "-i",
        str(ssh_key_path),
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-p",
        str(ssh_port),
        f"{ssh_user}@{public_ip}",
        "sudo cat /etc/wireguard/keys/server_public.key",
    ]
    key = _run(cmd).strip()
    if not _WG_PUB_RE.match(key):
        raise ValueError("unexpected WireGuard public key format fetched over SSH")
    return key


def _region_from_country(country_code: str) -> str:
    cc = (country_code or "").upper()
    if cc in ("US", "CA", "MX"):
        return "Americas"
    return "Europe"


def _upsert_server(
    *,
    hcloud_server_id: str,
    hcloud_server_name: str,
    hcloud_location: str,
    location: str,
    city: str,
    country: str,
    country_code: str,
    latitude: Optional[float],
    longitude: Optional[float],
    hcloud_server_type: str,
    hcloud_server_state: str,
    public_ip: str,
    wg_public_key: str,
    wg_port: int,
    allowed_ips: str = "0.0.0.0/0, ::/0",
) -> str:
    db = SessionLocal()
    try:
        existing = (
            db.query(VPNServer)
            .filter((VPNServer.hcloud_server_id == hcloud_server_id) | (VPNServer.server_id == hcloud_server_name))
            .first()
        )

        endpoint = f"{public_ip}:{wg_port}"
        if existing:
            existing.server_id = hcloud_server_name
            existing.location = location
            existing.city = city
            existing.country = country
            existing.country_code = country_code
            existing.region = _region_from_country(country_code)
            existing.latitude = latitude
            existing.longitude = longitude

            existing.hcloud_server_id = hcloud_server_id
            existing.hcloud_server_name = hcloud_server_name
            existing.hcloud_location = hcloud_location
            existing.hcloud_server_type = hcloud_server_type
            existing.hcloud_server_state = hcloud_server_state

            existing.public_ip = public_ip
            existing.endpoint = endpoint
            existing.wg_listen_port = wg_port
            existing.wg_public_key = wg_public_key
            existing.allowed_ips = allowed_ips
            if existing.wg_private_key_encrypted is None:
                existing.wg_private_key_encrypted = ""
            existing.status = "active"
            db.commit()
            return f"updated:{existing.server_id}"

        server = VPNServer(
            server_id=hcloud_server_name,
            location=location,
            country=country,
            country_code=country_code,
            city=city,
            region=_region_from_country(country_code),
            latitude=latitude,
            longitude=longitude,
            hcloud_server_id=hcloud_server_id,
            hcloud_server_name=hcloud_server_name,
            hcloud_location=hcloud_location,
            hcloud_server_type=hcloud_server_type,
            hcloud_server_state=hcloud_server_state,
            public_ip=public_ip,
            endpoint=endpoint,
            wg_listen_port=wg_port,
            wg_public_key=wg_public_key,
            wg_private_key_encrypted="",  # Server private key is stored on the server, not in the backend.
            allowed_ips=allowed_ips,
            status="active",
            health_status="unknown",
            max_connections=1000,
            current_connections=0,
            tier_restriction=None,
            performance_score=100.0,
        )
        db.add(server)
        db.commit()
        return f"created:{server.server_id}"
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync Hetzner VPN servers into SecureWave database")
    parser.add_argument(
        "--terraform-dir",
        default=str(PROJECT_ROOT / "infrastructure" / "hetzner"),
        help="Path to Terraform module directory (default: infrastructure/hetzner)",
    )
    parser.add_argument(
        "--wg-port",
        type=int,
        default=DEFAULT_WG_PORT,
        help="WireGuard listen port (default: 51820)",
    )
    parser.add_argument(
        "--fetch-wg-public-key",
        action="store_true",
        help="Fetch WireGuard public key from each server via SSH (recommended)",
    )
    parser.add_argument(
        "--ssh-user",
        default=os.getenv("WG_SSH_USER", "securewave"),
        help="SSH user for fetching server public key (default: WG_SSH_USER or 'securewave')",
    )
    parser.add_argument(
        "--ssh-key-path",
        default=os.getenv("WG_SSH_KEY_PATH", ""),
        help="SSH key path for fetching server public key (default: WG_SSH_KEY_PATH)",
    )
    parser.add_argument(
        "--wg-public-key",
        default="",
        help="WireGuard server public key (only suitable for single-server setups)",
    )

    args = parser.parse_args()

    terraform_dir = Path(args.terraform_dir).resolve()
    if not terraform_dir.exists():
        raise SystemExit(f"Terraform dir not found: {terraform_dir}")

    outputs = _read_terraform_outputs(terraform_dir)

    token = os.getenv("HETZNER_API_TOKEN", "").strip()
    if not token:
        raise SystemExit("HETZNER_API_TOKEN must be set")

    ssh_key_path = Path(args.ssh_key_path).expanduser().resolve() if args.ssh_key_path else None
    if args.fetch_wg_public_key and not ssh_key_path:
        raise SystemExit("--fetch-wg-public-key requires --ssh-key-path (or WG_SSH_KEY_PATH)")

    results: list[str] = []
    for hcloud_id, name, ipv4 in zip(outputs.server_ids, outputs.server_names, outputs.server_ipv4):
        api = _hcloud_get(token, f"/servers/{hcloud_id}")
        server = api.get("server") or {}
        server_type = (server.get("server_type") or {}).get("name") or ""
        state = server.get("status") or "unknown"
        dc = server.get("datacenter") or {}
        loc = dc.get("location") or {}
        hcloud_location = (loc.get("name") or "").strip() or "unknown"
        city = (loc.get("city") or "").strip() or hcloud_location.upper()
        country_code = (loc.get("country") or "").strip().upper() or "ZZ"
        latitude = loc.get("latitude")
        longitude = loc.get("longitude")
        # Hetzner does not provide full country names in all API contexts; use the code when unknown.
        country = country_code
        location = f"{city}, {country_code}"

        if server_type and server_type != "cx33":
            raise SystemExit(f"Refusing to register server_type={server_type} (policy: cx33 only)")

        wg_public_key = (args.wg_public_key or "").strip()
        if args.fetch_wg_public_key:
            wg_public_key = _fetch_wg_public_key_over_ssh(
                ipv4,
                ssh_user=args.ssh_user,
                ssh_key_path=ssh_key_path,  # type: ignore[arg-type]
            )
        if not wg_public_key:
            raise SystemExit(
                "WireGuard server public key missing. Provide --wg-public-key or use --fetch-wg-public-key."
            )

        results.append(
            _upsert_server(
                hcloud_server_id=str(hcloud_id),
                hcloud_server_name=str(name),
                hcloud_location=hcloud_location,
                location=location,
                city=city,
                country=country,
                country_code=country_code,
                latitude=latitude if isinstance(latitude, (int, float)) else None,
                longitude=longitude if isinstance(longitude, (int, float)) else None,
                hcloud_server_type=server_type or "cx33",
                hcloud_server_state=state,
                public_ip=str(ipv4),
                wg_public_key=wg_public_key,
                wg_port=args.wg_port,
            )
        )

    print("\n".join(results))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
