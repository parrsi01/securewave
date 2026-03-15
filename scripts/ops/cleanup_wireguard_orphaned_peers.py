#!/usr/bin/env python3
from __future__ import annotations

import argparse
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sqlalchemy.orm import Session

from database.session import SessionLocal
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer

logger = logging.getLogger("securewave.wg_orphan_cleanup")


def _run_command(argv: list[str]) -> str:
    result = subprocess.run(  # nosec B603
        argv,
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout.strip()


def _live_peer_keys(interface: str) -> set[str]:
    raw = _run_command(["wg", "show", interface, "peers"])
    return {line.strip() for line in raw.splitlines() if line.strip()}


def _local_public_key(interface: str) -> str:
    key = _run_command(["wg", "show", interface, "public-key"]).strip()
    if not key:
        raise RuntimeError(f"WireGuard interface {interface} did not return a public key")
    return key


def _resolve_local_server(
    db: Session,
    *,
    interface: str,
    server_id: str | None,
    public_key: str | None,
) -> VPNServer:
    if server_id:
        server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
        if server is None:
            raise RuntimeError(f"VPN server_id {server_id!r} was not found in the database")
        return server

    effective_public_key = (public_key or "").strip() or _local_public_key(interface)
    server = db.query(VPNServer).filter(VPNServer.wg_public_key == effective_public_key).first()
    if server is None:
        raise RuntimeError(
            "Could not match the local WireGuard public key to a vpn_servers row. "
            "Pass --server-id explicitly or sync the server metadata."
        )
    return server


def _expected_peer_keys(db: Session, server: VPNServer) -> set[str]:
    rows: Iterable[tuple[str]] = (
        db.query(WireGuardPeer.public_key)
        .filter(
            WireGuardPeer.server_id == server.id,
            WireGuardPeer.is_revoked.is_(False),
            WireGuardPeer.is_active.is_(True),
        )
        .all()
    )
    return {public_key.strip() for (public_key,) in rows if public_key and public_key.strip()}


def _remove_peer(interface: str, public_key: str, *, dry_run: bool) -> None:
    if dry_run:
        logger.info("dry_run peer_remove interface=%s public_key=%s", interface, public_key)
        return
    subprocess.run(  # nosec B603
        ["wg", "set", interface, "peer", public_key, "remove"],
        check=True,
        text=True,
        capture_output=True,
    )
    logger.info("peer_removed interface=%s public_key=%s", interface, public_key)


def _persist_config(interface: str, *, dry_run: bool) -> None:
    if dry_run:
        logger.info("dry_run persist interface=%s", interface)
        return
    subprocess.run(  # nosec B603
        ["wg-quick", "save", interface],
        check=True,
        text=True,
        capture_output=True,
    )
    logger.info("config_persisted interface=%s", interface)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Remove WireGuard peers from the local interface when they no longer exist in the SecureWave DB.",
    )
    parser.add_argument("--interface", default="wg0", help="WireGuard interface name (default: wg0)")
    parser.add_argument(
        "--server-id",
        default=os.getenv("SECUREWAVE_SERVER_ID") or os.getenv("VPN_SERVER_ID"),
        help="Explicit SecureWave server_id for this node",
    )
    parser.add_argument(
        "--public-key",
        default=os.getenv("SECUREWAVE_WG_PUBLIC_KEY"),
        help="Explicit local WireGuard public key; overrides `wg show <iface> public-key` detection",
    )
    parser.add_argument("--dry-run", action="store_true", help="Log peers that would be removed without mutating wg0")
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="Skip `wg-quick save` after removing peers",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    db: Session | None = None
    try:
        db = SessionLocal()
        server = _resolve_local_server(
            db,
            interface=args.interface,
            server_id=args.server_id,
            public_key=args.public_key,
        )
        expected = _expected_peer_keys(db, server)
        live = _live_peer_keys(args.interface)
        orphaned = sorted(live - expected)

        logger.info(
            "reconcile_start interface=%s server_id=%s expected=%d live=%d orphaned=%d dry_run=%s",
            args.interface,
            server.server_id,
            len(expected),
            len(live),
            len(orphaned),
            args.dry_run,
        )

        for public_key in orphaned:
            _remove_peer(args.interface, public_key, dry_run=args.dry_run)

        if orphaned and not args.no_save:
            _persist_config(args.interface, dry_run=args.dry_run)

        logger.info(
            "reconcile_complete interface=%s server_id=%s removed=%d",
            args.interface,
            server.server_id,
            len(orphaned),
        )
        return 0
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        logger.error(
            "wireguard_command_failed returncode=%s command=%s stderr=%s stdout=%s",
            exc.returncode,
            exc.cmd,
            stderr,
            stdout,
        )
        return 1
    except Exception as exc:
        logger.error("cleanup_failed error=%s", exc)
        return 1
    finally:
        if db is not None:
            db.close()


if __name__ == "__main__":
    raise SystemExit(main())
