import base64
import os
import secrets
import shutil
import subprocess
from io import BytesIO
from pathlib import Path
from typing import Tuple

import qrcode
from cryptography.fernet import Fernet
from dotenv import load_dotenv

from models.user import User

# Load environment variables
load_dotenv()


class WireGuardService:
    def __init__(self):
        self.base_dir = Path(os.getenv("WG_DATA_DIR", "/wg")).expanduser()
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self.users_dir = self.base_dir / "users"
        self.users_dir.mkdir(parents=True, exist_ok=True)
        self.server_private_path = self.base_dir / "server_private.key"
        self.server_public_path = self.base_dir / "server_public.key"
        self.endpoint = os.getenv("WG_ENDPOINT", "securewave-app.azurewebsites.net:51820")
        self.dns = os.getenv("WG_DNS", "1.1.1.1")
        self.fernet = self._load_fernet()
        self.mock_mode = self._detect_mock_mode()
        self.ensure_server_keys()

    def _detect_mock_mode(self) -> bool:
        if os.getenv("WG_MOCK_MODE", "").lower() == "true":
            return True
        wg_binary = shutil.which("wg")
        tun_exists = Path("/dev/net/tun").exists()
        return wg_binary is None or not tun_exists

    def _load_fernet(self):
        key = os.getenv("WG_ENCRYPTION_KEY")
        if not key:
            return None
        key_bytes = key.encode()
        if len(key_bytes) != 44:
            key_bytes = base64.urlsafe_b64encode(key_bytes.ljust(32, b"0")[:32])
        return Fernet(key_bytes)

    def generate_keypair(self) -> Tuple[str, str]:
        try:
            private_key = subprocess.check_output(["wg", "genkey"]).decode().strip()
            public_key = subprocess.check_output(["wg", "pubkey"], input=private_key.encode()).decode().strip()
            return private_key, public_key
        except Exception:
            private_bytes = secrets.token_bytes(32)
            private_key = base64.b64encode(private_bytes).decode()
            public_key = base64.b64encode(secrets.token_bytes(32)).decode()
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

    def ensure_server_keys(self) -> None:
        if self.server_private_path.exists() and self.server_public_path.exists():
            return
        private_key, public_key = self.generate_keypair()
        self.server_private_path.write_text(private_key)
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
        server_public_key = self.server_public_path.read_text().strip()

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
        config_path.write_text(config_content)
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
        config_path.write_text(config_content)
        return config_path, config_content

    def qr_from_config(self, config_text: str) -> str:
        img = qrcode.make(config_text)
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode()
