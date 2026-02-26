#!/usr/bin/env python3
"""
Local VPN registry repair utility.

Use this to inspect/fix the backend `vpn_servers` registry when the app only
shows one location/protocol because the DB is sparse or protocol flags are off.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Iterable

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from database.session import SessionLocal, create_tables
from models.vpn_server import VPNServer


@dataclass(frozen=True)
class SeedServer:
    server_id: str
    location: str
    country: str
    country_code: str
    city: str
    region: str
    hcloud_location: str
    public_ip: str
    endpoint: str


DEFAULT_SEED_SERVERS = [
    SeedServer(
        server_id="us-east-ash-1",
        location="Ashburn, US",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        public_ip="138.199.204.139",
        endpoint="138.199.204.139:51820",
    ),
    SeedServer(
        server_id="de-fsn1-1",
        location="Falkenstein, DE",
        country="Germany",
        country_code="DE",
        city="Falkenstein",
        region="Europe",
        hcloud_location="fsn1",
        public_ip="203.0.113.21",
        endpoint="203.0.113.21:51820",
    ),
    SeedServer(
        server_id="de-nbg1-1",
        location="Nuremberg, DE",
        country="Germany",
        country_code="DE",
        city="Nuremberg",
        region="Europe",
        hcloud_location="nbg1",
        public_ip="203.0.113.22",
        endpoint="203.0.113.22:51820",
    ),
    SeedServer(
        server_id="fi-hel1-1",
        location="Helsinki, FI",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        region="Europe",
        hcloud_location="hel1",
        public_ip="203.0.113.23",
        endpoint="203.0.113.23:51820",
    ),
]


def _ensure_tables() -> None:
    create_tables()


def _iter_servers(db) -> Iterable[VPNServer]:
    return db.query(VPNServer).order_by(VPNServer.server_id.asc()).all()


def _print_servers(db) -> None:
    rows = list(_iter_servers(db))
    if not rows:
        print("vpn_servers: (empty)")
        return
    print(f"vpn_servers: {len(rows)} row(s)")
    for s in rows:
        print(
            f"- {s.server_id} | {s.location} | status={s.status} health={s.health_status} "
            f"wg={int(bool(s.supports_wireguard))} ovpn={int(bool(s.supports_openvpn))} "
            f"ikev2={int(bool(s.supports_ikev2))} hcloud={s.hcloud_location} ip={s.public_ip}"
        )


def _seed_defaults(db, *, overwrite_placeholders: bool = False) -> int:
    changed = 0
    for seed in DEFAULT_SEED_SERVERS:
        row = db.query(VPNServer).filter(VPNServer.server_id == seed.server_id).first()
        if row is None:
            row = VPNServer(
                server_id=seed.server_id,
                location=seed.location,
                country=seed.country,
                country_code=seed.country_code,
                city=seed.city,
                region=seed.region,
                hcloud_location=seed.hcloud_location,
                public_ip=seed.public_ip,
                endpoint=seed.endpoint,
                wg_public_key="TEST_WG_PUBLIC_KEY_PLACEHOLDER",
                wg_private_key_encrypted="",
                status="active",
                health_status="unknown",
                hcloud_server_state="running",
                max_connections=1000,
                current_connections=0,
                performance_score=100.0,
                supports_wireguard=True,
                supports_openvpn=False,
                supports_ikev2=False,
            )
            db.add(row)
            changed += 1
            continue

        if overwrite_placeholders:
            row.location = seed.location
            row.country = seed.country
            row.country_code = seed.country_code
            row.city = seed.city
            row.region = seed.region
            row.hcloud_location = seed.hcloud_location
            if not row.public_ip:
                row.public_ip = seed.public_ip
            if not row.endpoint:
                row.endpoint = seed.endpoint
            changed += 1

    if changed:
        db.commit()
    return changed


def _enable_protocols(db, protocols: set[str]) -> int:
    changed = 0
    for row in _iter_servers(db):
        before = (bool(row.supports_openvpn), bool(row.supports_ikev2))
        if "openvpn" in protocols:
            row.supports_openvpn = True
            row.openvpn_endpoint = row.openvpn_endpoint or row.public_ip
            row.openvpn_port = row.openvpn_port or 1194
            row.openvpn_transport = row.openvpn_transport or "udp"
        if "ikev2" in protocols:
            row.supports_ikev2 = True
            row.ikev2_remote_id = row.ikev2_remote_id or None
        after = (bool(row.supports_openvpn), bool(row.supports_ikev2))
        if before != after:
            changed += 1
    if changed:
        db.commit()
    return changed


def _mark_all_active(db) -> int:
    changed = 0
    for row in _iter_servers(db):
        before = (row.status, row.health_status, row.hcloud_server_state)
        row.status = "active"
        row.health_status = row.health_status or "unknown"
        row.hcloud_server_state = row.hcloud_server_state or "running"
        after = (row.status, row.health_status, row.hcloud_server_state)
        if before != after:
            changed += 1
    if changed:
        db.commit()
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair local SecureWave VPN server registry")
    parser.add_argument("--init-db", action="store_true", help="Create DB tables if missing")
    parser.add_argument("--list", action="store_true", help="List current vpn_servers rows")
    parser.add_argument(
        "--seed-defaults",
        action="store_true",
        help="Seed multiple default locations if missing (safe local fallback).",
    )
    parser.add_argument(
        "--overwrite-placeholders",
        action="store_true",
        help="When seeding defaults, update placeholder fields on existing rows.",
    )
    parser.add_argument(
        "--enable-protocols",
        default="",
        help="Comma-separated protocols to enable on all servers (openvpn,ikev2).",
    )
    parser.add_argument(
        "--mark-all-active",
        action="store_true",
        help="Force all vpn_servers rows to active/running for local debugging.",
    )
    args = parser.parse_args()

    if args.init_db:
        _ensure_tables()

    db = SessionLocal()
    try:
        if args.seed_defaults:
            changed = _seed_defaults(db, overwrite_placeholders=args.overwrite_placeholders)
            print(f"seed_defaults changed={changed}")

        if args.mark_all_active:
            changed = _mark_all_active(db)
            print(f"mark_all_active changed={changed}")

        if args.enable_protocols:
            protocols = {p.strip().lower() for p in args.enable_protocols.split(",") if p.strip()}
            invalid = protocols - {"openvpn", "ikev2"}
            if invalid:
                raise SystemExit(f"unsupported protocols: {', '.join(sorted(invalid))}")
            changed = _enable_protocols(db, protocols)
            print(f"enable_protocols changed={changed} protocols={','.join(sorted(protocols))}")

        if args.list or (not args.seed_defaults and not args.enable_protocols and not args.mark_all_active):
            _print_servers(db)
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
