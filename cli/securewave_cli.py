#!/usr/bin/env python3
"""
SecureWave operator CLI.

Commands:
  securewave vpn seed add-node
  securewave vpn rotate server-key
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Optional

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
os.environ.setdefault("AUTO_CREATE_TABLES", "false")

from models import user, subscription, audit_log, vpn_server, vpn_connection, wireguard_peer, auth_refresh_token  # noqa: E402,F401
from database.session import SessionLocal  # noqa: E402
from services.vpn_server_key_lifecycle import VPNServerKeyLifecycleService  # noqa: E402


def _print_json(payload: dict) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def handle_seed_add_node(args: argparse.Namespace) -> int:
    db = SessionLocal()
    try:
        service = VPNServerKeyLifecycleService(db)
        private_key: Optional[str] = None
        if args.wg_private_key_file:
            private_key = Path(args.wg_private_key_file).read_text(encoding="utf-8").strip()

        server = service.seed_add_node(
            server_id=args.server_id,
            location=args.location,
            country=args.country,
            country_code=args.country_code,
            city=args.city,
            hcloud_location=args.hcloud_location,
            public_ip=args.public_ip,
            wg_public_key=args.wg_public_key,
            wg_private_key=private_key,
            wg_listen_port=args.wg_listen_port,
            allowed_ips=args.allowed_ips,
            region=args.region,
            max_connections=args.max_connections,
            tier_restriction=args.tier_restriction,
            hcloud_server_name=args.hcloud_server_name,
            hcloud_server_id=args.hcloud_server_id,
            hcloud_server_type=args.hcloud_server_type,
        )
        _print_json(
            {
                "status": "ok",
                "command": "securewave vpn seed add-node",
                "server_id": server.server_id,
                "endpoint": server.endpoint,
                "wg_key_version": server.wg_key_version,
            }
        )
        return 0
    finally:
        db.close()


async def _rotate_server_key_async(args: argparse.Namespace) -> int:
    db = SessionLocal()
    try:
        service = VPNServerKeyLifecycleService(db)
        result = await service.rotate_server_key(
            server_id=args.server_id,
            apply_remote=args.apply_remote,
            interface=args.interface,
            ssh_user=args.ssh_user,
            ssh_key_path=args.ssh_key_path,
            ssh_port=args.ssh_port,
        )
        result.update(
            {
                "status": "ok",
                "command": "securewave vpn rotate server-key",
            }
        )
        _print_json(result)
        return 0
    finally:
        db.close()


def handle_rotate_server_key(args: argparse.Namespace) -> int:
    return asyncio.run(_rotate_server_key_async(args))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="securewave", description="SecureWave operator CLI")
    subparsers = parser.add_subparsers(dest="area", required=True)

    vpn = subparsers.add_parser("vpn", help="VPN operations")
    vpn_sub = vpn.add_subparsers(dest="vpn_cmd", required=True)

    seed = vpn_sub.add_parser("seed", help="Seed VPN resources")
    seed_sub = seed.add_subparsers(dest="seed_cmd", required=True)

    add_node = seed_sub.add_parser("add-node", help="Add or update a VPN node in the registry")
    add_node.add_argument("--server-id", required=True)
    add_node.add_argument("--location", required=True)
    add_node.add_argument("--country", required=True)
    add_node.add_argument("--country-code", required=True)
    add_node.add_argument("--city", required=True)
    add_node.add_argument("--hcloud-location", required=True)
    add_node.add_argument("--public-ip", required=True)
    add_node.add_argument("--wg-public-key", required=True)
    add_node.add_argument("--wg-private-key-file")
    add_node.add_argument("--wg-listen-port", type=int, default=51820)
    add_node.add_argument("--allowed-ips", default="0.0.0.0/0, ::/0")
    add_node.add_argument("--region", default="Europe")
    add_node.add_argument("--max-connections", type=int, default=1000)
    add_node.add_argument("--tier-restriction")
    add_node.add_argument("--hcloud-server-name")
    add_node.add_argument("--hcloud-server-id")
    add_node.add_argument("--hcloud-server-type", default="cx33")
    add_node.set_defaults(handler=handle_seed_add_node)

    rotate = vpn_sub.add_parser("rotate", help="Rotate VPN secrets")
    rotate_sub = rotate.add_subparsers(dest="rotate_cmd", required=True)

    server_key = rotate_sub.add_parser("server-key", help="Rotate server WireGuard keypair")
    server_key.add_argument("--server-id", required=True)
    server_key.add_argument(
        "--apply-remote",
        action="store_true",
        help="Apply the new private key on the remote server over SSH",
    )
    server_key.add_argument("--interface", default="wg0")
    server_key.add_argument("--ssh-user")
    server_key.add_argument("--ssh-key-path")
    server_key.add_argument("--ssh-port", type=int)
    server_key.set_defaults(handler=handle_rotate_server_key)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
