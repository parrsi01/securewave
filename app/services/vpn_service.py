import base64
import secrets
import shutil
import subprocess
from typing import Tuple

from app.core import config


def generate_keypair() -> Tuple[str, str]:
    wg_binary = shutil.which("wg")
    if wg_binary:
        try:
            private_key = subprocess.check_output(["wg", "genkey"]).decode().strip()
            public_key = subprocess.check_output(["wg", "pubkey"], input=private_key.encode()).decode().strip()
            return private_key, public_key
        except Exception:
            pass

    private_bytes = secrets.token_bytes(32)
    private_key = base64.b64encode(private_bytes).decode()
    public_key = base64.b64encode(secrets.token_bytes(32)).decode()
    return private_key, public_key


def allocate_ip_for_device(device_id: int) -> str:
    octet = (device_id % 240) + 10
    return f"10.8.0.{octet}/32"


def build_wireguard_config(device_id: int) -> str:
    private_key, _public_key = generate_keypair()
    client_ip = allocate_ip_for_device(device_id)

    if not config.WG_SERVER_PUBLIC_KEY:
        # TODO: load server public key from database or secrets manager.
        server_public_key = ""
    else:
        server_public_key = config.WG_SERVER_PUBLIC_KEY

    config_content = (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"Address = {client_ip}\n"
        f"DNS = {config.WG_DNS}\n\n"
        "[Peer]\n"
        f"PublicKey = {server_public_key}\n"
        f"Endpoint = {config.WG_ENDPOINT}\n"
        f"AllowedIPs = {config.WG_ALLOWED_IPS}\n"
        f"PersistentKeepalive = {config.WG_PERSISTENT_KEEPALIVE}\n"
    )

    return config_content
