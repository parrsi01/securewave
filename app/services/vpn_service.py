import base64
import secrets
import shutil
import subprocess
from typing import Tuple, Optional

from sqlalchemy.orm import Session

from app.core import config
from app.models.vpn_server import VPNServer


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


def get_server(db: Session, server_id: Optional[str] = None) -> Optional[VPNServer]:
    query = db.query(VPNServer).filter(VPNServer.is_active == True)
    if server_id:
        return query.filter(VPNServer.server_id == server_id).first()
    return query.filter(VPNServer.status == "active").first()


def list_servers(db: Session) -> list[VPNServer]:
    return db.query(VPNServer).filter(VPNServer.is_active == True).all()


def create_server(
    db: Session,
    server_id: str,
    location: str,
    endpoint: str,
    wg_public_key: str,
    region: Optional[str] = None,
    dns: Optional[str] = None,
    allowed_ips: Optional[str] = None,
    persistent_keepalive: Optional[str] = None,
    status: str = "active",
) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location=location,
        region=region,
        endpoint=endpoint,
        wg_public_key=wg_public_key,
        dns=dns or config.WG_DNS,
        allowed_ips=allowed_ips or config.WG_ALLOWED_IPS,
        persistent_keepalive=persistent_keepalive or config.WG_PERSISTENT_KEEPALIVE,
        status=status,
        is_active=True,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def deactivate_server(db: Session, server_id: str) -> Optional[VPNServer]:
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        return None
    server.is_active = False
    db.commit()
    return server


def build_wireguard_config(device_id: int, server: VPNServer) -> str:
    private_key, _public_key = generate_keypair()
    client_ip = allocate_ip_for_device(device_id)

    config_content = (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"Address = {client_ip}\n"
        f"DNS = {server.dns or config.WG_DNS}\n\n"
        "[Peer]\n"
        f"PublicKey = {server.wg_public_key}\n"
        f"Endpoint = {server.endpoint}\n"
        f"AllowedIPs = {server.allowed_ips or config.WG_ALLOWED_IPS}\n"
        f"PersistentKeepalive = {server.persistent_keepalive or config.WG_PERSISTENT_KEEPALIVE}\n"
    )

    return config_content
