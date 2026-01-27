"""
Admin endpoints for WireGuard peer management.
Allows auto-registration of peers on the WG VM.
"""
import os
import re
import shutil
import subprocess  # nosec B404 - controlled subprocess usage with validated args
import ipaddress
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService

router = APIRouter()

# WireGuard VM details (from Azure setup)
WG_VM_NAME = os.getenv("WG_VM_NAME", "securewave-wg")
WG_RESOURCE_GROUP = os.getenv("WG_RESOURCE_GROUP", "SecureWaveRG")
WG_KEY_PATTERN = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")


def _resolve_az_cli() -> str:
    az_path = shutil.which("az")
    if not az_path:
        raise FileNotFoundError("Azure CLI not available. Run the command manually on the WG VM.")
    return az_path


def _validate_wg_peer_inputs(public_key: str, client_ip: str) -> None:
    if not WG_KEY_PATTERN.match(public_key):
        raise HTTPException(status_code=400, detail="Invalid WireGuard public key format")
    try:
        ipaddress.ip_address(client_ip)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid client IP address") from exc


class PeerInfo(BaseModel):
    user_id: int
    email: str
    client_public_key: str
    client_ip: str
    registered: bool


class RegisterPeerRequest(BaseModel):
    user_id: int


class RegisterPeerResponse(BaseModel):
    success: bool
    user_id: int
    client_public_key: str
    client_ip: str
    message: str
    wg_command: Optional[str] = None


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Dependency that requires admin privileges."""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user


@router.get("/peers/pending", response_model=List[PeerInfo])
def list_pending_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    List all users who have allocated a WireGuard config but are not yet
    registered as peers on the WireGuard server.
    """
    wg_service = WireGuardService()

    # Find users with wg_public_key who aren't registered yet
    pending_users = db.query(User).filter(
        User.wg_public_key.isnot(None),
        User.wg_peer_registered == False
    ).all()

    return [
        PeerInfo(
            user_id=u.id,
            email=u.email,
            client_public_key=u.wg_public_key,
            client_ip=wg_service.allocate_ip(u.id),
            registered=u.wg_peer_registered
        )
        for u in pending_users
    ]


@router.get("/peers/all", response_model=List[PeerInfo])
def list_all_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """List all users with WireGuard configs (registered and pending)."""
    wg_service = WireGuardService()

    users_with_keys = db.query(User).filter(
        User.wg_public_key.isnot(None)
    ).all()

    return [
        PeerInfo(
            user_id=u.id,
            email=u.email,
            client_public_key=u.wg_public_key,
            client_ip=wg_service.allocate_ip(u.id),
            registered=u.wg_peer_registered
        )
        for u in users_with_keys
    ]


@router.post("/peers/register", response_model=RegisterPeerResponse)
def register_peer(
    request: RegisterPeerRequest,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Register a single peer on the WireGuard server using Azure VM Run Command.
    """
    user = db.query(User).filter(User.id == request.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not user.wg_public_key:
        raise HTTPException(status_code=400, detail="User has no WireGuard config allocated")

    wg_service = WireGuardService()
    client_ip = wg_service.allocate_ip(user.id)

    _validate_wg_peer_inputs(user.wg_public_key, client_ip)

    # Build the wg set command
    wg_command = f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}"
    persist_command = "sudo wg-quick save wg0"
    full_command = f"{wg_command} && {persist_command}"

    try:
        # Execute on Azure VM using Run Command
        az_path = _resolve_az_cli()
        result = subprocess.run(  # nosec B603 - args are validated and not user-controlled beyond key/ip
            [
                az_path, "vm", "run-command", "invoke",
                "-g", WG_RESOURCE_GROUP,
                "-n", WG_VM_NAME,
                "--command-id", "RunShellScript",
                "--scripts", full_command
            ],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode == 0:
            # Mark peer as registered
            user.wg_peer_registered = True
            db.commit()

            return RegisterPeerResponse(
                success=True,
                user_id=user.id,
                client_public_key=user.wg_public_key,
                client_ip=client_ip,
                message="Peer registered successfully on WireGuard server",
                wg_command=wg_command
            )
        else:
            return RegisterPeerResponse(
                success=False,
                user_id=user.id,
                client_public_key=user.wg_public_key,
                client_ip=client_ip,
                message=f"Failed to register peer: {result.stderr}",
                wg_command=wg_command
            )

    except subprocess.TimeoutExpired:
        return RegisterPeerResponse(
            success=False,
            user_id=user.id,
            client_public_key=user.wg_public_key,
            client_ip=client_ip,
            message="Timeout executing Azure VM Run Command",
            wg_command=wg_command
        )
    except FileNotFoundError as exc:
        return RegisterPeerResponse(
            success=False,
            user_id=user.id,
            client_public_key=user.wg_public_key,
            client_ip=client_ip,
            message=str(exc),
            wg_command=wg_command
        )


@router.post("/peers/register-all")
def register_all_pending_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Register all pending peers on the WireGuard server in bulk.
    """
    wg_service = WireGuardService()

    pending_users = db.query(User).filter(
        User.wg_public_key.isnot(None),
        User.wg_peer_registered == False
    ).all()

    if not pending_users:
        return {"message": "No pending peers to register", "registered": 0}

    for user in pending_users:
        client_ip = wg_service.allocate_ip(user.id)
        _validate_wg_peer_inputs(user.wg_public_key, client_ip)

    # Build bulk command
    commands = []
    for user in pending_users:
        client_ip = wg_service.allocate_ip(user.id)
        commands.append(f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}")

    commands.append("sudo wg-quick save wg0")
    full_command = " && ".join(commands)

    results = []
    try:
        az_path = _resolve_az_cli()
        result = subprocess.run(  # nosec B603 - args are validated and not user-controlled beyond key/ip
            [
                az_path, "vm", "run-command", "invoke",
                "-g", WG_RESOURCE_GROUP,
                "-n", WG_VM_NAME,
                "--command-id", "RunShellScript",
                "--scripts", full_command
            ],
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode == 0:
            # Mark all as registered
            for user in pending_users:
                user.wg_peer_registered = True
                results.append({
                    "user_id": user.id,
                    "email": user.email,
                    "client_ip": wg_service.allocate_ip(user.id),
                    "success": True
                })
            db.commit()

            return {
                "message": f"Successfully registered {len(pending_users)} peers",
                "registered": len(pending_users),
                "results": results
            }
        else:
            return {
                "message": f"Failed to register peers: {result.stderr}",
                "registered": 0,
                "command": full_command
            }

    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return {
            "message": f"Could not auto-register: {str(e)}. Run manually on WG VM.",
            "registered": 0,
            "command": full_command,
            "peers": [
                {
                    "user_id": u.id,
                    "public_key": u.wg_public_key,
                    "client_ip": wg_service.allocate_ip(u.id)
                }
                for u in pending_users
            ]
        }


@router.post("/peers/mark-registered/{user_id}")
def mark_peer_registered(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Manually mark a peer as registered (when registered outside this API).
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.wg_peer_registered = True
    db.commit()

    return {"message": f"User {user_id} marked as registered", "user_id": user_id}


@router.get("/peers/command/{user_id}")
def get_peer_command(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Get the wg set command for a specific user (for manual registration).
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not user.wg_public_key:
        raise HTTPException(status_code=400, detail="User has no WireGuard config")

    wg_service = WireGuardService()
    client_ip = wg_service.allocate_ip(user.id)

    return {
        "user_id": user_id,
        "email": user.email,
        "client_public_key": user.wg_public_key,
        "client_ip": client_ip,
        "wg_command": f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}",
        "persist_command": "sudo wg-quick save wg0"
    }
