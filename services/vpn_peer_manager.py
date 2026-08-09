"""The single-target WireGuard peer lifecycle used by Linux Beta 1."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.wireguard_service import WireGuardService


class VPNPeerManager:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.wg_service = WireGuardService()

    def _next_address(self) -> str:
        for last_octet in range(10, 250):
            address = f"10.8.0.{last_octet}/32"
            if not self.db.query(WireGuardPeer).filter(
                WireGuardPeer.ipv4_address == address
            ).first():
                return address
        raise ValueError("The WireGuard address pool is full")

    def create_peer(
        self,
        user: User,
        server: VPNServer | None = None,
        device_name: str | None = None,
        device_type: str | None = None,
        **_: object,
    ) -> WireGuardPeer:
        private_key, public_key = self.wg_service.generate_keypair()
        peer = WireGuardPeer(
            user_id=user.id,
            server_id=server.id if server else None,
            public_key=public_key,
            private_key_encrypted=self.wg_service.encrypt_private_key(private_key),
            ipv4_address=self._next_address(),
            device_name=device_name,
            device_type=device_type,
            is_active=True,
            is_revoked=False,
            key_version=1,
            next_key_rotation_at=datetime.utcnow() + timedelta(days=90),
        )
        self.db.add(peer)
        try:
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            raise ValueError("Unable to create a unique WireGuard device") from exc
        self.db.refresh(peer)
        return peer

    def get_or_create_peer(
        self,
        user: User,
        server: VPNServer | None = None,
        device_name: str | None = None,
    ) -> WireGuardPeer:
        query = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        )
        peer = query.order_by(WireGuardPeer.created_at.asc()).first()
        return peer or self.create_peer(user, server, device_name, "linux")

    def generate_config(self, peer: WireGuardPeer, server: VPNServer | None = None) -> str:
        if server is None and peer.server_id:
            server = self.db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server is None:
            raise ValueError("No WireGuard target is assigned")
        private_key = self.wg_service.decrypt_private_key(peer.private_key_encrypted)
        return (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {peer.ipv4_address}\n"
            f"DNS = {server.dns_servers}\n\n"
            "[Peer]\n"
            f"PublicKey = {server.wg_public_key}\n"
            f"Endpoint = {server.endpoint}\n"
            f"AllowedIPs = {server.allowed_ips or '0.0.0.0/0, ::/0'}\n"
            "PersistentKeepalive = 25\n"
        )

    def rotate_peer_keys(self, peer_id: int, commit: bool = True) -> WireGuardPeer:
        peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).one()
        private_key, public_key = self.wg_service.generate_keypair()
        peer.private_key_encrypted = self.wg_service.encrypt_private_key(private_key)
        peer.public_key = public_key
        peer.key_version = int(peer.key_version or 0) + 1
        peer.last_key_rotation_at = datetime.utcnow()
        if commit:
            self.db.commit()
            self.db.refresh(peer)
        return peer

    def revoke_peer(self, peer_id: int) -> bool:
        peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).first()
        if peer is None:
            return False
        peer.is_active = False
        peer.is_revoked = True
        peer.revoked_at = datetime.utcnow()
        self.db.commit()
        return True


def get_peer_manager(db: Session) -> VPNPeerManager:
    return VPNPeerManager(db)
