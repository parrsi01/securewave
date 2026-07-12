import base64
import logging
import os
import shutil
import stat
import subprocess  # nosec B404 - controlled subprocess usage
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
from dotenv import load_dotenv

from utils.env_validation import validate_fernet_key, is_production

from models.user import User

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)


class WireGuardService:
    def __init__(self):
        self.base_dir = Path(os.getenv("WG_DATA_DIR", "/wg")).expanduser()
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
        self.endpoint = os.getenv("WG_ENDPOINT", "127.0.0.1:51820")
        # Prefer SECUREWAVE_TUNNEL_DNS (used by the profile provisioning path).
        raw_dns = os.getenv("SECUREWAVE_TUNNEL_DNS", "").strip() or os.getenv("WG_DNS", "").strip()
        if not raw_dns:
            raw_dns = "94.140.14.14,94.140.15.15"
        dns_parts = [p.strip() for p in raw_dns.split(",") if p.strip()]
        self.dns = ",".join(dns_parts) if dns_parts else "94.140.14.14,94.140.15.15"
        self.server_public_override = os.getenv("WG_SERVER_PUBLIC_KEY", "").strip() or None
        self.fernet = self._load_fernet()
        self.wg_path = shutil.which("wg")
        self.mock_mode = self._detect_mock_mode()
        self.ensure_server_keys()

    def _detect_mock_mode(self) -> bool:
        """
        Determine if we're in mock mode for WireGuard operations.

        Priority:
        1. If WG_MOCK_MODE is explicitly set to 'false', use real mode
        2. If WG_MOCK_MODE is explicitly set to 'true', use mock mode
        3. If not set, auto-detect based on environment
        """
        mock_env = os.getenv("WG_MOCK_MODE", "").lower().strip()

        # Explicit false = real mode (don't auto-detect)
        if mock_env == "false":
            return False

        # Explicit true = mock mode
        if mock_env == "true":
            logger.warning("WG_MOCK_MODE=true: WireGuard operations are mocked (no real tunnel).")
            return True

        if is_production():
            raise RuntimeError("WG_MOCK_MODE must be explicitly set to false in production")

        # Auto-detect only if not explicitly configured
        tun_exists = Path("/dev/net/tun").exists()
        mock = self.wg_path is None or not tun_exists
        if mock:
            reason = []
            if self.wg_path is None:
                reason.append("'wg' binary not found")
            if not tun_exists:
                reason.append("/dev/net/tun missing")
            logger.warning("WG_MOCK_MODE not set: entering mock mode (%s).", ", ".join(reason))
        return mock

    def _load_fernet(self):
        key = os.getenv("WG_ENCRYPTION_KEY")
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

        # In production, do not silently proceed without wg when not in explicit mock mode.
        if is_production() and not self.mock_mode:
            raise RuntimeError("WireGuard key generation requires the 'wg' binary in production")

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
        return base64.b64encode(key.encode()).decode()

    def decrypt_private_key(self, encrypted: str) -> str:
        if not encrypted:
            return ""
        if self.fernet:
            return self.fernet.decrypt(encrypted.encode()).decode()
        return base64.b64decode(encrypted.encode()).decode()

    @staticmethod
    def _write_secret_file(path: Path, content: str) -> None:
        """Write a file and restrict permissions to owner-only (0600)."""
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
        octet = (user_id % 240) + 10
        return f"10.8.0.{octet}/32"

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

        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {self.dns}\n\n"
            "[Peer]\n"
            f"PublicKey = {server_public_key}\n"
            f"Endpoint = {self.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
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

        # Use server-specific endpoint and public key
        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {self.dns}\n\n"
            "[Peer]\n"
            f"PublicKey = {server.wg_public_key}\n"
            f"Endpoint = {server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
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
