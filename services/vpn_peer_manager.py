"""
SecureWave VPN - Peer Management Service
Manages WireGuard peers, keys, IP allocation, and configuration generation
"""

import logging
import secrets
import base64
import subprocess
from datetime import datetime, timedelta
from typing import Optional, Tuple, List, Dict
from io import BytesIO
from sqlalchemy.orm import Session
import qrcode

from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.wireguard_service import WireGuardService

logger = logging.getLogger(__name__)

# Configuration
DEFAULT_KEY_ROTATION_DAYS = 90
IP_POOL_START = "10.8.0"
IP_POOL_END = 254


class VPNPeerManager:
    """
    Production-grade VPN peer management service
    Handles peer lifecycle, key rotation, and config generation
    """

    def __init__(self, db: Session):
        """Initialize peer manager"""
        self.db = db
        self.wg_service = WireGuardService()

    # ===========================
    # PEER CREATION & MANAGEMENT
    # ===========================

    def create_peer(
        self,
        user: User,
        server: Optional[VPNServer] = None,
        device_name: Optional[str] = None,
        device_type: Optional[str] = None
    ) -> WireGuardPeer:
        """
        Create new WireGuard peer for user

        Args:
            user: User object
            server: Optional specific server (None = any server)
            device_name: Optional device name
            device_type: Optional device type (windows, macos, linux, ios, android)

        Returns:
            WireGuardPeer object
        """
        try:
            # Generate keypair
            private_key, public_key = self.wg_service.generate_keypair()

            # Encrypt private key
            private_key_encrypted = self.wg_service.encrypt_private_key(private_key)

            # Allocate IP address
            ipv4_address = self._allocate_ip_address(user.id)

            # Calculate next rotation date
            next_rotation = datetime.utcnow() + timedelta(days=DEFAULT_KEY_ROTATION_DAYS)

            # Create peer
            peer = WireGuardPeer(
                user_id=user.id,
                server_id=server.id if server else None,
                public_key=public_key,
                private_key_encrypted=private_key_encrypted,
                ipv4_address=ipv4_address,
                device_name=device_name,
                device_type=device_type,
                is_active=True,
                is_revoked=False,
                key_version=1,
                next_key_rotation_at=next_rotation,
            )

            self.db.add(peer)
            self.db.commit()
            self.db.refresh(peer)

            logger.info(f"✓ WireGuard peer created for user {user.id} (IP: {ipv4_address})")
            return peer

        except Exception as e:
            logger.error(f"✗ Failed to create peer: {e}")
            self.db.rollback()
            raise

    def get_or_create_peer(
        self,
        user: User,
        server: Optional[VPNServer] = None,
        device_name: Optional[str] = None
    ) -> WireGuardPeer:
        """
        Get existing peer or create new one

        Args:
            user: User object
            server: Optional server
            device_name: Optional device name

        Returns:
            WireGuardPeer object
        """
        # Try to find existing active peer
        query = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_active == True,
            WireGuardPeer.is_revoked == False
        )

        if server:
            query = query.filter(WireGuardPeer.server_id == server.id)
        else:
            query = query.filter(WireGuardPeer.server_id == None)

        peer = query.first()

        if peer:
            logger.info(f"✓ Found existing peer for user {user.id}")
            return peer

        # Create new peer
        return self.create_peer(user, server, device_name)

    def list_user_peers(self, user_id: int, include_revoked: bool = False) -> List[WireGuardPeer]:
        """
        List all peers for a user

        Args:
            user_id: User ID
            include_revoked: Include revoked peers

        Returns:
            List of WireGuardPeer objects
        """
        query = self.db.query(WireGuardPeer).filter(WireGuardPeer.user_id == user_id)

        if not include_revoked:
            query = query.filter(WireGuardPeer.is_revoked == False)

        return query.order_by(WireGuardPeer.created_at.desc()).all()

    def revoke_peer(self, peer_id: int) -> bool:
        """
        Revoke peer (invalidate keys)

        Args:
            peer_id: Peer ID

        Returns:
            True if successful
        """
        try:
            peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).first()

            if not peer:
                return False

            peer.is_revoked = True
            peer.is_active = False
            peer.revoked_at = datetime.utcnow()
            self.db.commit()

            logger.info(f"✓ Peer {peer_id} revoked")
            return True

        except Exception as e:
            logger.error(f"✗ Failed to revoke peer: {e}")
            self.db.rollback()
            return False

    def delete_peer(self, peer_id: int) -> bool:
        """
        Permanently delete peer

        Args:
            peer_id: Peer ID

        Returns:
            True if successful
        """
        try:
            peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).first()

            if not peer:
                return False

            self.db.delete(peer)
            self.db.commit()

            logger.info(f"✓ Peer {peer_id} deleted")
            return True

        except Exception as e:
            logger.error(f"✗ Failed to delete peer: {e}")
            self.db.rollback()
            return False

    # ===========================
    # CONFIGURATION GENERATION
    # ===========================

    def generate_config(
        self,
        peer: WireGuardPeer,
        server: Optional[VPNServer] = None
    ) -> str:
        """
        Generate WireGuard configuration for peer

        Args:
            peer: WireGuardPeer object
            server: Optional server (uses peer.server if not provided)

        Returns:
            Configuration string
        """
        if not server and peer.server_id:
            server = self.db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()

        if not server:
            raise ValueError("No server specified")

        # Decrypt private key
        private_key = self.wg_service.decrypt_private_key(peer.private_key_encrypted)

        # Generate config
        config = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {peer.ipv4_address}\n"
            f"DNS = {server.dns_servers}\n\n"
            "[Peer]\n"
            f"PublicKey = {server.wg_public_key}\n"
            f"Endpoint = {server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
        )

        return config

    def generate_config_qr_code(
        self,
        peer: WireGuardPeer,
        server: Optional[VPNServer] = None
    ) -> bytes:
        """
        Generate QR code for configuration (mobile devices)

        Args:
            peer: WireGuardPeer object
            server: Optional server

        Returns:
            PNG image bytes
        """
        config = self.generate_config(peer, server)

        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(config)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")

        # Convert to bytes
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        return buffer.getvalue()

    def generate_config_file(
        self,
        peer: WireGuardPeer,
        server: Optional[VPNServer] = None,
        filename: Optional[str] = None
    ) -> Tuple[str, str]:
        """
        Generate configuration file

        Args:
            peer: WireGuardPeer object
            server: Optional server
            filename: Optional filename

        Returns:
            Tuple of (filename, config_content)
        """
        config = self.generate_config(peer, server)

        if not filename:
            server_name = server.server_id if server else "default"
            filename = f"securewave-{server_name}.conf"

        return filename, config

    # ===========================
    # KEY ROTATION
    # ===========================

    def rotate_peer_keys(self, peer_id: int) -> WireGuardPeer:
        """
        Rotate WireGuard keys for peer

        Args:
            peer_id: Peer ID

        Returns:
            Updated WireGuardPeer object
        """
        try:
            peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).first()

            if not peer:
                raise ValueError("Peer not found")

            # Generate new keypair
            private_key, public_key = self.wg_service.generate_keypair()

            # Encrypt private key
            private_key_encrypted = self.wg_service.encrypt_private_key(private_key)

            # Update peer
            peer.private_key_encrypted = private_key_encrypted
            peer.public_key = public_key
            peer.key_version += 1
            peer.last_key_rotation_at = datetime.utcnow()
            peer.next_key_rotation_at = datetime.utcnow() + timedelta(days=DEFAULT_KEY_ROTATION_DAYS)

            self.db.commit()
            self.db.refresh(peer)

            logger.info(f"✓ Keys rotated for peer {peer_id} (version {peer.key_version})")
            return peer

        except Exception as e:
            logger.error(f"✗ Failed to rotate keys: {e}")
            self.db.rollback()
            raise

    def rotate_all_due_keys(self) -> int:
        """
        Rotate keys for all peers that are due

        Returns:
            Number of peers rotated
        """
        try:
            # Find peers due for rotation
            due_peers = self.db.query(WireGuardPeer).filter(
                WireGuardPeer.is_active == True,
                WireGuardPeer.is_revoked == False,
                WireGuardPeer.next_key_rotation_at <= datetime.utcnow()
            ).all()

            count = 0
            for peer in due_peers:
                try:
                    self.rotate_peer_keys(peer.id)
                    count += 1
                except Exception as e:
                    logger.error(f"Failed to rotate keys for peer {peer.id}: {e}")
                    continue

            logger.info(f"✓ Rotated keys for {count} peers")
            return count

        except Exception as e:
            logger.error(f"✗ Batch key rotation failed: {e}")
            return 0

    # ===========================
    # IP ADDRESS MANAGEMENT
    # ===========================

    def _allocate_ip_address(self, user_id: int) -> str:
        """
        Allocate IP address for user

        Args:
            user_id: User ID

        Returns:
            IPv4 address (CIDR notation)
        """
        # Simple allocation based on user ID
        # In production, you'd want a more sophisticated IP pool management
        octet = (user_id % (IP_POOL_END - 10)) + 10
        return f"{IP_POOL_START}.{octet}/32"

    def get_allocated_ips(self) -> List[str]:
        """
        Get list of all allocated IP addresses

        Returns:
            List of IP addresses
        """
        peers = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.is_active == True,
            WireGuardPeer.is_revoked == False
        ).all()

        return [peer.ipv4_address for peer in peers]

    # ===========================
    # STATISTICS
    # ===========================

    def get_peer_stats(self, peer_id: int) -> Optional[Dict]:
        """
        Get statistics for a peer

        Args:
            peer_id: Peer ID

        Returns:
            Statistics dictionary
        """
        peer = self.db.query(WireGuardPeer).filter(WireGuardPeer.id == peer_id).first()

        if not peer:
            return None

        return {
            "peer_id": peer.id,
            "user_id": peer.user_id,
            "is_active": peer.is_active,
            "is_revoked": peer.is_revoked,
            "key_version": peer.key_version,
            "days_since_rotation": peer.days_since_rotation,
            "needs_rotation": peer.needs_rotation,
            "is_recently_active": peer.is_recently_active,
            "total_data_sent_mb": round(peer.total_data_sent / 1024 / 1024, 2),
            "total_data_received_mb": round(peer.total_data_received / 1024 / 1024, 2),
            "last_handshake_at": peer.last_handshake_at.isoformat() if peer.last_handshake_at else None,
        }

    def get_system_peer_stats(self) -> Dict:
        """
        Get system-wide peer statistics

        Returns:
            Statistics dictionary
        """
        total_peers = self.db.query(WireGuardPeer).count()
        active_peers = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.is_active == True,
            WireGuardPeer.is_revoked == False
        ).count()

        revoked_peers = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.is_revoked == True
        ).count()

        due_rotation = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.is_active == True,
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.next_key_rotation_at <= datetime.utcnow()
        ).count()

        return {
            "total_peers": total_peers,
            "active_peers": active_peers,
            "revoked_peers": revoked_peers,
            "peers_due_rotation": due_rotation,
            "ip_addresses_allocated": active_peers,
        }


# Singleton instance
_peer_manager = None


def get_peer_manager(db: Session) -> VPNPeerManager:
    """Get peer manager instance"""
    return VPNPeerManager(db)
