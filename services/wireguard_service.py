import base64
import logging
import shutil
import stat
import subprocess  # nosec B404 - controlled subprocess usage
import ipaddress
from io import BytesIO
from pathlib import Path
from typing import Tuple

import qrcode
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    PrivateFormat,
    PublicFormat,
    NoEncryption,
)

from config.settings import get_settings
from utils.env_validation import validate_fernet_key, is_production

from models.user import User
from services.wireguard_tuning import tune_wireguard

logger = logging.getLogger(__name__)
SETTINGS = get_settings()


class WireGuardService:
    def __init__(self):
        self.base_dir = SETTINGS.wg_data_dir
        self.base_dir.mkdir(parents=True, exist_ok=True)
        try:
            self.base_dir.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        except OSError:
            pass
        self.users_dir = self.base_dir / "users"
        self.users_dir.mkdir(parents=True, exist_ok=True)
        try:
            self.users_dir.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        except OSError:
            pass
        self.server_private_path = self.base_dir / "server_private.key"
        self.server_public_path = self.base_dir / "server_public.key"
        self.endpoint = SETTINGS.vpn_server_endpoint
        self.dns = SETTINGS.wg_dns
        self.server_public_override = SETTINGS.wg_server_public_key
        self.fernet = self._load_fernet()
        self.wg_path = shutil.which("wg")
        self.ensure_server_keys()

    def _load_fernet(self):
        key = SETTINGS.wg_encryption_key
        issue = validate_fernet_key(key)
        if issue:
            if is_production():
                raise RuntimeError(f"WG_ENCRYPTION_KEY {issue} in production")
            logger.warning("WG_ENCRYPTION_KEY %s; private key encryption disabled", issue)
            return None
        return Fernet(key.encode())

    def generate_keypair(self) -> Tuple[str, str]:
        if self.wg_path:
            try:
                private_key = subprocess.check_output([self.wg_path, "genkey"]).decode().strip()  # nosec B603
                public_key = subprocess.check_output(  # nosec B603
                    [self.wg_path, "pubkey"], input=private_key.encode()
                ).decode().strip()
                return private_key, public_key
            except Exception as e:
                logger.warning("wg key generation failed; falling back to X25519: %s", e)

        # WireGuard keys are Curve25519 (X25519) keys, base64-encoded.
        private = X25519PrivateKey.generate()
        private_bytes = private.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
        public_bytes = private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        private_key = base64.b64encode(private_bytes).decode()
        public_key = base64.b64encode(public_bytes).decode()
        return private_key, public_key

    def encrypt_private_key(self, key: str) -> str:
        if self.fernet:
            return self.fernet.encrypt(key.encode()).decode()
        raise RuntimeError(
            "WG_ENCRYPTION_KEY is not set or invalid. "
            "Private keys cannot be stored without encryption."
        )

    def decrypt_private_key(self, encrypted: str) -> str:
        if not encrypted:
            return ""
        if self.fernet:
            return self.fernet.decrypt(encrypted.encode()).decode()
        raise RuntimeError(
            "WG_ENCRYPTION_KEY is not set or invalid. "
            "Cannot decrypt private key without an encryption key."
        )

    @staticmethod
    def _write_secret_file(path: Path, content: str) -> None:
        """Write a file and restrict permissions to owner-only (0600).

        L-9: WireGuard client config files contain the peer PrivateKey in plaintext.
        This is unavoidable — the WireGuard kernel interface requires the raw key.
        Mitigation: files are written with 0600 (owner read/write only) so no other
        OS user can read the key. Files are stored under wg_data_dir (default: /tmp/wg_data
        in dev, /opt/securewave/wg_data in prod) which should itself be 0700.
        Callers are responsible for deleting config files when they are no longer needed.
        """
        path.write_text(content)
        try:
            path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass  # Windows or permission-restricted environment

    def ensure_server_keys(self) -> None:
        if self.server_public_override:
            return
        if self.server_private_path.exists() and self.server_public_path.exists():
            return
        private_key, public_key = self.generate_keypair()
        self._write_secret_file(self.server_private_path, private_key)
        self.server_public_path.write_text(public_key)

    def allocate_ip(self, user_id: int) -> str:
        """
        Deterministic fallback allocator using dynamic /22 expansion blocks.

        NOTE:
        - Primary allocation path is `VPNPeerManager._allocate_ip_address` with DB uniqueness.
        - This fallback keeps legacy flows functional and removes the historical 240-IP cap.
        """
        base_cidr = SETTINGS.wg_ip_pool_base_cidr
        try:
            base_network = ipaddress.ip_network(base_cidr, strict=False)
        except ValueError:
            base_network = ipaddress.ip_network("10.8.0.0/22", strict=False)
        if base_network.prefixlen != 22:
            base_network = ipaddress.ip_network(f"{base_network.network_address}/22", strict=False)

        reserved_hosts = 10
        usable_per_block = max(1, (base_network.num_addresses - 2) - reserved_hosts)
        idx = max(0, int(user_id) - 1)
        block_offset = idx // usable_per_block
        host_offset = idx % usable_per_block

        block_start = int(base_network.network_address) + (block_offset * base_network.num_addresses)
        block_network = ipaddress.ip_network(f"{ipaddress.IPv4Address(block_start)}/{base_network.prefixlen}", strict=False)
        host_int = int(block_network.network_address) + 1 + reserved_hosts + host_offset
        return f"{ipaddress.IPv4Address(host_int)}/32"

    def generate_client_config(self, user: User) -> Tuple[Path, str]:
        if not user.wg_private_key_encrypted or not user.wg_public_key:
            private_key, public_key = self.generate_keypair()
            user.wg_private_key_encrypted = self.encrypt_private_key(private_key)
            user.wg_public_key = public_key
        else:
            private_key = self.decrypt_private_key(user.wg_private_key_encrypted)
            public_key = user.wg_public_key

        client_ip = self.allocate_ip(user.id)
        server_public_key = self.server_public_override or self.server_public_path.read_text().strip()

        tuning = tune_wireguard(
            endpoint=self.endpoint,
            client_ip=None,
            forwarded_for=None,
            observed_latency_ms=None,
            device_type=None,
        )
        mtu_line = f"MTU = {tuning.mtu}\n" if tuning.mtu else ""
        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {self.dns}\n"
            f"{mtu_line}"
            "\n"
            "[Peer]\n"
            f"PublicKey = {server_public_key}\n"
            f"Endpoint = {self.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            f"PersistentKeepalive = {tuning.keepalive_seconds}\n"
        )

        config_path = self.users_dir / f"{user.id}.conf"
        self._write_secret_file(config_path, config_content)
        return config_path, config_content

    def config_exists(self, user_id: int) -> bool:
        return (self.users_dir / f"{user_id}.conf").exists()

    def config_path_for_server(self, user_id: int, server_id: str) -> Path:
        return self.users_dir / f"{user_id}_{server_id}.conf"

    def config_exists_for_server(self, user_id: int, server_id: str) -> bool:
        return self.config_path_for_server(user_id, server_id).exists()

    def get_config(self, user_id: int) -> str:
        config_path = self.users_dir / f"{user_id}.conf"
        if not config_path.exists():
            raise FileNotFoundError("Configuration not generated")
        return config_path.read_text()

    def get_config_for_server(self, user_id: int, server_id: str) -> str:
        config_path = self.config_path_for_server(user_id, server_id)
        if not config_path.exists():
            raise FileNotFoundError("Configuration not generated")
        return config_path.read_text()

    def generate_client_config_for_server(self, user: User, server) -> Tuple[Path, str]:
        """
        Generate client config for a specific VPN server

        Args:
            user: User object
            server: VPNServer object with endpoint and wg_public_key

        Returns:
            Tuple of (config_path, config_content)
        """
        # Generate or retrieve user's keys
        if not user.wg_private_key_encrypted or not user.wg_public_key:
            private_key, public_key = self.generate_keypair()
            user.wg_private_key_encrypted = self.encrypt_private_key(private_key)
            user.wg_public_key = public_key
        else:
            private_key = self.decrypt_private_key(user.wg_private_key_encrypted)
            public_key = user.wg_public_key

        client_ip = self.allocate_ip(user.id)

        # Use server-specific endpoint and public key; apply adaptive tuning.
        tuning = tune_wireguard(
            endpoint=server.endpoint,
            client_ip=None,
            forwarded_for=None,
            observed_latency_ms=None,
            device_type=None,
        )
        mtu_line = f"MTU = {tuning.mtu}\n" if tuning.mtu else ""
        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {self.dns}\n"
            f"{mtu_line}"
            "\n"
            "[Peer]\n"
            f"PublicKey = {server.wg_public_key}\n"
            f"Endpoint = {server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            f"PersistentKeepalive = {tuning.keepalive_seconds}\n"
        )

        # Save config with server_id in filename
        config_path = self.config_path_for_server(user.id, server.server_id)
        self._write_secret_file(config_path, config_content)
        return config_path, config_content

    def qr_from_config(self, config_text: str) -> str:
        img = qrcode.make(config_text)
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode()
