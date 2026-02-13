"""
Server key lifecycle operations: node seeding and safe key rotation.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy.orm import Session

from models.vpn_server import VPNServer
from services.wireguard_service import WireGuardService
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db
from utils.input_sanitizer import (
    sanitize_allowed_ips,
    sanitize_endpoint,
    sanitize_identifier,
    sanitize_wireguard_key,
)


class VPNServerKeyLifecycleService:
    """Service for VPN node seed/rotation workflows."""

    def __init__(self, db: Session):
        self.db = db
        self.wg = WireGuardService()

    def seed_add_node(
        self,
        *,
        server_id: str,
        location: str,
        country: str,
        country_code: str,
        city: str,
        hcloud_location: str,
        public_ip: str,
        wg_public_key: str,
        wg_private_key: Optional[str] = None,
        wg_listen_port: int = 51820,
        allowed_ips: str = "0.0.0.0/0, ::/0",
        region: str = "Europe",
        max_connections: int = 1000,
        tier_restriction: Optional[str] = None,
        hcloud_server_name: Optional[str] = None,
        hcloud_server_id: Optional[str] = None,
        hcloud_server_type: str = "cx33",
    ) -> VPNServer:
        """Create or update a VPN node in the registry."""
        safe_server_id = sanitize_identifier(server_id, field_name="server_id")
        safe_wg_public_key = sanitize_wireguard_key(wg_public_key, field_name="wg_public_key")
        safe_allowed_ips = sanitize_allowed_ips(allowed_ips)
        endpoint = sanitize_endpoint(f"{public_ip}:{wg_listen_port}")

        existing = self.db.query(VPNServer).filter(VPNServer.server_id == safe_server_id).first()
        encrypted_private = ""
        if wg_private_key:
            encrypted_private = self.wg.encrypt_private_key(wg_private_key.strip())

        if existing:
            existing.location = location.strip()
            existing.country = country.strip()
            existing.country_code = country_code.strip().upper()[:2]
            existing.city = city.strip()
            existing.region = region.strip() if region else existing.region
            existing.hcloud_location = hcloud_location.strip()
            existing.hcloud_server_name = hcloud_server_name
            existing.hcloud_server_id = hcloud_server_id
            existing.hcloud_server_type = hcloud_server_type
            existing.public_ip = public_ip.strip()
            existing.endpoint = endpoint
            existing.wg_public_key = safe_wg_public_key
            existing.allowed_ips = safe_allowed_ips
            existing.wg_listen_port = wg_listen_port
            existing.max_connections = max_connections
            existing.tier_restriction = tier_restriction
            existing.status = "active"
            if encrypted_private:
                existing.wg_private_key_encrypted = encrypted_private
            self.db.commit()
            self.db.refresh(existing)
            return existing

        server = VPNServer(
            server_id=safe_server_id,
            location=location.strip(),
            country=country.strip(),
            country_code=country_code.strip().upper()[:2],
            city=city.strip(),
            region=region.strip() if region else None,
            hcloud_location=hcloud_location.strip(),
            hcloud_server_name=hcloud_server_name,
            hcloud_server_id=hcloud_server_id,
            hcloud_server_type=hcloud_server_type,
            public_ip=public_ip.strip(),
            endpoint=endpoint,
            wg_public_key=safe_wg_public_key,
            wg_private_key_encrypted=encrypted_private,
            allowed_ips=safe_allowed_ips,
            wg_listen_port=wg_listen_port,
            status="active",
            health_status="unknown",
            hcloud_server_state="running",
            max_connections=max_connections,
            tier_restriction=tier_restriction,
        )
        self.db.add(server)
        self.db.commit()
        self.db.refresh(server)
        return server

    async def rotate_server_key(
        self,
        *,
        server_id: str,
        apply_remote: bool = False,
        interface: str = "wg0",
        ssh_user: Optional[str] = None,
        ssh_key_path: Optional[str] = None,
        ssh_port: Optional[int] = None,
    ) -> dict[str, Any]:
        """Rotate one server keypair and optionally apply on the remote node."""
        safe_server_id = sanitize_identifier(server_id, field_name="server_id")
        server = self.db.query(VPNServer).filter(VPNServer.server_id == safe_server_id).first()
        if not server:
            raise ValueError(f"Server not found: {safe_server_id}")

        new_private_key, new_public_key = self.wg.generate_keypair()
        new_public_key = sanitize_wireguard_key(new_public_key, field_name="wg_public_key")
        encrypted_private = self.wg.encrypt_private_key(new_private_key)

        if apply_remote:
            manager = get_wireguard_server_manager()
            conn = server_connection_from_db(server)
            if ssh_user:
                conn.ssh_user = ssh_user
            if ssh_key_path:
                conn.ssh_key_path = ssh_key_path
            if ssh_port:
                conn.ssh_port = int(ssh_port)

            ok, message, remote_public_key = await manager.rotate_server_key(
                conn,
                new_private_key,
                interface=interface,
            )
            if not ok:
                raise RuntimeError(f"Remote key rotation failed: {message}")
            if remote_public_key:
                new_public_key = sanitize_wireguard_key(remote_public_key, field_name="wg_public_key")

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        rotation_days = int(os.getenv("SERVER_KEY_ROTATION_DAYS", "30"))
        next_rotation = now + timedelta(days=max(1, rotation_days))

        server.wg_public_key = new_public_key
        server.wg_private_key_encrypted = encrypted_private
        server.wg_key_version = int(server.wg_key_version or 1) + 1
        server.wg_last_rotated_at = now
        server.wg_next_rotation_at = next_rotation
        self.db.add(server)
        self.db.commit()
        self.db.refresh(server)

        return {
            "server_id": server.server_id,
            "wg_key_version": server.wg_key_version,
            "rotated_at": now.replace(tzinfo=timezone.utc).isoformat(),
            "next_rotation_at": next_rotation.replace(tzinfo=timezone.utc).isoformat(),
            "remote_applied": apply_remote,
        }
