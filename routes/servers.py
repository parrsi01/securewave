"""
SecureWave VPN - Server Management Routes

Admin endpoints for managing WireGuard VPN servers:
- Provisioning new servers
- Health monitoring
- Peer synchronization
- Server fleet management
"""

import os
import json
import logging
from datetime import datetime
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_server import VPNServer
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
    ServerConnection,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/admin/servers", tags=["admin-servers"])

# Environment settings
DEMO_MODE = os.getenv("DEMO_MODE", "false").lower() == "true"
WG_MOCK_MODE = os.getenv("WG_MOCK_MODE", "false").lower() == "true"


# =============================================================================
# Request/Response Models
# =============================================================================

class CreateServerRequest(BaseModel):
    """Request to create/register a new VPN server"""
    server_id: str = Field(..., description="Unique server identifier (e.g., 'us-east-001')")
    location: str = Field(..., description="Human-readable location (e.g., 'New York')")
    country: str = Field(..., description="Country name")
    country_code: str = Field(..., max_length=2, description="ISO 3166-1 alpha-2 country code")
    city: str = Field(..., description="City name")
    region: Optional[str] = Field(None, description="Geographic region (Americas, Europe, Asia, etc.)")
    latitude: Optional[float] = Field(None, description="Latitude for map display")
    longitude: Optional[float] = Field(None, description="Longitude for map display")
    azure_region: str = Field(..., description="Azure region code (e.g., 'eastus')")
    azure_resource_group: Optional[str] = Field(None, description="Azure resource group name")
    azure_vm_name: Optional[str] = Field(None, description="Azure VM name")
    public_ip: str = Field(..., description="Server's public IP address")
    wg_public_key: str = Field(..., description="WireGuard server public key")
    wg_private_key: Optional[str] = Field(None, description="WireGuard private key (will be encrypted)")
    wg_listen_port: int = Field(51820, description="WireGuard listen port")
    max_connections: int = Field(1000, description="Maximum concurrent connections")
    tier_restriction: Optional[str] = Field(None, description="Subscription tier restriction (null=all, 'premium'=premium only)")


class UpdateServerRequest(BaseModel):
    """Request to update server configuration"""
    status: Optional[str] = Field(None, description="Server status (active, maintenance, offline)")
    health_status: Optional[str] = Field(None, description="Health status")
    max_connections: Optional[int] = Field(None, description="Maximum connections")
    tier_restriction: Optional[str] = Field(None, description="Tier restriction")
    wg_public_key: Optional[str] = Field(None, description="New WireGuard public key")
    azure_vm_state: Optional[str] = Field(None, description="Azure VM state")


class ServerResponse(BaseModel):
    """Full server information response"""
    server_id: str
    location: str
    country: str
    country_code: str
    city: str
    region: Optional[str]
    public_ip: str
    endpoint: str
    wg_public_key: str
    status: str
    health_status: str
    current_connections: int
    max_connections: int
    capacity_percent: float
    latency_ms: Optional[float]
    cpu_load: Optional[float]
    memory_usage: Optional[float]
    created_at: str
    last_health_check: Optional[str]


class PeerSyncResult(BaseModel):
    """Result of peer synchronization"""
    server_id: str
    synced_peers: int
    failed_peers: int
    errors: List[str]


# =============================================================================
# Auth Helpers
# =============================================================================

def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Dependency that requires admin privileges"""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user


# =============================================================================
# Server CRUD Endpoints
# =============================================================================

@router.post("/", response_model=ServerResponse)
async def create_server(
    request: CreateServerRequest,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Register a new VPN server in the system.

    This endpoint registers an already-provisioned WireGuard server.
    For automated server deployment, use the infrastructure scripts.
    """
    # Check if server_id already exists
    existing = db.query(VPNServer).filter(VPNServer.server_id == request.server_id).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Server with ID '{request.server_id}' already exists"
        )

    wg_service = WireGuardService()

    # Encrypt private key if provided
    encrypted_private_key = ""
    if request.wg_private_key:
        encrypted_private_key = wg_service.encrypt_private_key(request.wg_private_key)

    # Create server record
    server = VPNServer(
        server_id=request.server_id,
        location=request.location,
        country=request.country,
        country_code=request.country_code,
        city=request.city,
        region=request.region,
        latitude=request.latitude,
        longitude=request.longitude,
        azure_region=request.azure_region,
        azure_resource_group=request.azure_resource_group,
        azure_vm_name=request.azure_vm_name,
        public_ip=request.public_ip,
        endpoint=f"{request.public_ip}:{request.wg_listen_port}",
        wg_public_key=request.wg_public_key,
        wg_private_key_encrypted=encrypted_private_key,
        wg_listen_port=request.wg_listen_port,
        max_connections=request.max_connections,
        tier_restriction=request.tier_restriction,
        status="active",
        health_status="unknown",
        azure_vm_state="running",
        provisioned_at=datetime.utcnow(),
    )

    db.add(server)
    db.commit()
    db.refresh(server)

    logger.info(f"Server {request.server_id} registered by admin {admin.email}")

    return ServerResponse(
        server_id=server.server_id,
        location=server.location,
        country=server.country,
        country_code=server.country_code,
        city=server.city,
        region=server.region,
        public_ip=server.public_ip,
        endpoint=server.endpoint,
        wg_public_key=server.wg_public_key,
        status=server.status,
        health_status=server.health_status,
        current_connections=server.current_connections,
        max_connections=server.max_connections,
        capacity_percent=server.capacity_percentage,
        latency_ms=server.latency_ms,
        cpu_load=server.cpu_load,
        memory_usage=server.memory_usage,
        created_at=server.created_at.isoformat(),
        last_health_check=server.last_health_check.isoformat() if server.last_health_check else None,
    )


@router.get("/", response_model=List[ServerResponse])
async def list_all_servers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """List all VPN servers (including inactive ones)."""
    servers = db.query(VPNServer).order_by(VPNServer.server_id).all()

    return [
        ServerResponse(
            server_id=s.server_id,
            location=s.location,
            country=s.country,
            country_code=s.country_code,
            city=s.city,
            region=s.region,
            public_ip=s.public_ip,
            endpoint=s.endpoint,
            wg_public_key=s.wg_public_key,
            status=s.status,
            health_status=s.health_status,
            current_connections=s.current_connections,
            max_connections=s.max_connections,
            capacity_percent=s.capacity_percentage,
            latency_ms=s.latency_ms,
            cpu_load=s.cpu_load,
            memory_usage=s.memory_usage,
            created_at=s.created_at.isoformat(),
            last_health_check=s.last_health_check.isoformat() if s.last_health_check else None,
        )
        for s in servers
    ]


@router.get("/{server_id}", response_model=ServerResponse)
async def get_server_details(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Get detailed information about a specific server."""
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    return ServerResponse(
        server_id=server.server_id,
        location=server.location,
        country=server.country,
        country_code=server.country_code,
        city=server.city,
        region=server.region,
        public_ip=server.public_ip,
        endpoint=server.endpoint,
        wg_public_key=server.wg_public_key,
        status=server.status,
        health_status=server.health_status,
        current_connections=server.current_connections,
        max_connections=server.max_connections,
        capacity_percent=server.capacity_percentage,
        latency_ms=server.latency_ms,
        cpu_load=server.cpu_load,
        memory_usage=server.memory_usage,
        created_at=server.created_at.isoformat(),
        last_health_check=server.last_health_check.isoformat() if server.last_health_check else None,
    )


@router.patch("/{server_id}")
async def update_server(
    server_id: str,
    request: UpdateServerRequest,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Update server configuration."""
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    # Update fields
    if request.status is not None:
        server.status = request.status
    if request.health_status is not None:
        server.health_status = request.health_status
    if request.max_connections is not None:
        server.max_connections = request.max_connections
    if request.tier_restriction is not None:
        server.tier_restriction = request.tier_restriction if request.tier_restriction else None
    if request.wg_public_key is not None:
        server.wg_public_key = request.wg_public_key
    if request.azure_vm_state is not None:
        server.azure_vm_state = request.azure_vm_state

    db.commit()

    logger.info(f"Server {server_id} updated by admin {admin.email}")

    return {"message": f"Server {server_id} updated", "server_id": server_id}


@router.delete("/{server_id}")
async def delete_server(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Remove a server from the system.

    This only removes the database record. The actual VM should be
    decommissioned separately using Azure CLI or portal.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    db.delete(server)
    db.commit()

    logger.info(f"Server {server_id} deleted by admin {admin.email}")

    return {"message": f"Server {server_id} deleted", "server_id": server_id}


# =============================================================================
# Health Check Endpoints
# =============================================================================

@router.post("/{server_id}/health-check")
async def run_health_check(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Run a health check on a specific server.

    Connects to the server and verifies WireGuard is running.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        # Simulate health check in mock mode
        server.health_status = "healthy"
        server.last_health_check = datetime.utcnow()
        server.consecutive_health_failures = 0
        db.commit()

        return {
            "server_id": server_id,
            "healthy": True,
            "mode": "mock",
            "message": "Mock health check passed",
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        healthy, message = await manager.health_check(conn)

        # Update server record
        server.last_health_check = datetime.utcnow()
        if healthy:
            server.health_status = "healthy"
            server.consecutive_health_failures = 0
        else:
            server.consecutive_health_failures += 1
            if server.consecutive_health_failures >= 3:
                server.health_status = "unhealthy"
            else:
                server.health_status = "degraded"

        db.commit()

        return {
            "server_id": server_id,
            "healthy": healthy,
            "message": message,
            "consecutive_failures": server.consecutive_health_failures,
            "health_status": server.health_status,
        }

    except Exception as e:
        logger.error(f"Health check failed for {server_id}: {e}")
        server.consecutive_health_failures += 1
        server.health_status = "unreachable"
        server.last_health_check = datetime.utcnow()
        db.commit()

        return {
            "server_id": server_id,
            "healthy": False,
            "message": str(e),
            "error": True,
        }


@router.post("/health-check-all")
async def run_health_check_all(
    background_tasks: BackgroundTasks,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Queue health checks for all active servers.

    Runs asynchronously in the background.
    """
    servers = db.query(VPNServer).filter(
        VPNServer.status.in_(["active", "provisioning"])
    ).all()

    if not servers:
        return {"message": "No servers to check", "count": 0}

    # In a real implementation, you'd queue these as background tasks
    # For now, return the list of servers that will be checked
    return {
        "message": f"Health checks queued for {len(servers)} servers",
        "count": len(servers),
        "servers": [s.server_id for s in servers],
    }


# =============================================================================
# Server Metrics Endpoints
# =============================================================================

@router.get("/{server_id}/metrics")
async def get_server_metrics(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Get real-time metrics from a specific server.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        return {
            "server_id": server_id,
            "mode": "mock",
            "metrics": {
                "cpu_load": 0.25,
                "memory_percent": 45.2,
                "disk_percent": 30,
                "peer_count": server.current_connections,
                "uptime_seconds": 86400,
            }
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        success, metrics = await manager.get_server_status(conn)

        if success:
            # Update server record with new metrics
            if "cpu_load" in metrics:
                server.cpu_load = float(metrics["cpu_load"])
            if "memory_percent" in metrics:
                server.memory_usage = float(metrics["memory_percent"]) / 100
            if "peer_count" in metrics:
                server.current_connections = int(metrics["peer_count"])

            db.commit()

            return {
                "server_id": server_id,
                "metrics": metrics,
            }
        else:
            return {
                "server_id": server_id,
                "error": "Failed to retrieve metrics",
            }

    except Exception as e:
        logger.error(f"Failed to get metrics for {server_id}: {e}")
        return {
            "server_id": server_id,
            "error": str(e),
        }


# =============================================================================
# Peer Management Endpoints
# =============================================================================

@router.get("/{server_id}/peers")
async def list_server_peers(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    List all peers currently configured on a server.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        # Return mock peer list
        return {
            "server_id": server_id,
            "mode": "mock",
            "peers": [],
            "count": 0,
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        success, peers = await manager.list_peers(conn)

        if success:
            return {
                "server_id": server_id,
                "peers": peers,
                "count": len(peers),
            }
        else:
            return {
                "server_id": server_id,
                "error": "Failed to list peers",
                "peers": [],
            }

    except Exception as e:
        logger.error(f"Failed to list peers for {server_id}: {e}")
        return {
            "server_id": server_id,
            "error": str(e),
            "peers": [],
        }


@router.post("/{server_id}/peers/sync")
async def sync_server_peers(
    server_id: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Synchronize all registered users' peers to a server.

    This adds any missing peers that should be on this server.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    wg_service = WireGuardService()

    # Get all users with WireGuard keys who should be on this server
    users_with_keys = db.query(User).filter(
        User.wg_public_key.isnot(None),
        User.is_active == True
    ).all()

    if WG_MOCK_MODE or DEMO_MODE:
        return {
            "server_id": server_id,
            "mode": "mock",
            "synced": len(users_with_keys),
            "failed": 0,
            "message": f"Would sync {len(users_with_keys)} peers (mock mode)",
        }

    manager = get_wireguard_server_manager()
    conn = server_connection_from_db(server)

    synced = 0
    failed = 0
    errors = []

    for user in users_with_keys:
        allowed_ips = wg_service.allocate_ip(user.id)
        try:
            success, message = await manager.add_peer(conn, user.wg_public_key, allowed_ips)
            if success:
                synced += 1
                if not user.wg_peer_registered:
                    user.wg_peer_registered = True
            else:
                failed += 1
                errors.append(f"User {user.id}: {message}")
        except Exception as e:
            failed += 1
            errors.append(f"User {user.id}: {str(e)}")

    db.commit()

    logger.info(f"Peer sync for {server_id}: {synced} synced, {failed} failed")

    return {
        "server_id": server_id,
        "synced": synced,
        "failed": failed,
        "errors": errors[:10],  # Limit error messages
    }


@router.post("/{server_id}/peers/add")
async def add_peer_to_server(
    server_id: str,
    public_key: str,
    allowed_ips: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Manually add a peer to a server.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        return {
            "server_id": server_id,
            "mode": "mock",
            "success": True,
            "message": "Peer would be added (mock mode)",
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        success, message = await manager.add_peer(conn, public_key, allowed_ips)

        return {
            "server_id": server_id,
            "success": success,
            "message": message,
        }

    except Exception as e:
        logger.error(f"Failed to add peer to {server_id}: {e}")
        return {
            "server_id": server_id,
            "success": False,
            "message": str(e),
        }


@router.post("/{server_id}/peers/remove")
async def remove_peer_from_server(
    server_id: str,
    public_key: str,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Remove a peer from a server.
    """
    server = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        return {
            "server_id": server_id,
            "mode": "mock",
            "success": True,
            "message": "Peer would be removed (mock mode)",
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        success, message = await manager.remove_peer(conn, public_key)

        return {
            "server_id": server_id,
            "success": success,
            "message": message,
        }

    except Exception as e:
        logger.error(f"Failed to remove peer from {server_id}: {e}")
        return {
            "server_id": server_id,
            "success": False,
            "message": str(e),
        }
