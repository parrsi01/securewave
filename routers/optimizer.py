"""
VPN Optimizer API Router
Exposes ML-enhanced VPN server optimization endpoints
Auto-detects ML availability and adapts
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from models.user import User
from services.jwt_service import get_current_user
from services.vpn_optimizer import get_vpn_optimizer

router = APIRouter()


class ServerSelectionRequest(BaseModel):
    preferred_location: Optional[str] = None
    require_premium: bool = False


class ConnectionQualityReport(BaseModel):
    server_id: str
    actual_latency_ms: float
    actual_throughput_mbps: float


@router.post("/select-server")
def select_optimal_server(
    request: ServerSelectionRequest,
    current_user: User = Depends(get_current_user)
):
    """
    Select optimal VPN server using intelligent routing algorithm
    Returns best server based on current network conditions and user profile
    """
    optimizer = get_vpn_optimizer()

    # Determine if user has premium access
    is_premium = False
    if hasattr(current_user, 'subscription') and current_user.subscription:
        is_premium = current_user.subscription.is_active

    result = optimizer.select_optimal_server(
        user_id=current_user.id,
        user_location=request.preferred_location,
        is_premium=is_premium
    )

    if "error" in result:
        raise HTTPException(status_code=503, detail=result["error"])

    return result


@router.post("/report-quality")
def report_connection_quality(
    report: ConnectionQualityReport,
    current_user: User = Depends(get_current_user)
):
    """
    Report actual connection quality for continuous learning
    This improves future server selection accuracy
    """
    optimizer = get_vpn_optimizer()

    optimizer.report_connection_quality(
        user_id=current_user.id,
        server_id=report.server_id,
        actual_latency=report.actual_latency_ms,
        actual_throughput=report.actual_throughput_mbps
    )

    return {
        "status": "success",
        "message": "Quality report recorded, optimizer learning updated"
    }


@router.get("/stats")
def get_optimizer_stats(current_user: User = Depends(get_current_user)):
    """
    Get VPN optimizer performance statistics
    Shows optimizer metrics and server status
    """
    optimizer = get_vpn_optimizer()
    stats = optimizer.get_stats()

    return {
        "optimizer_stats": stats,
        "user_connection_state": {
            "user_id": current_user.id,
            "has_premium": hasattr(current_user, 'subscription') and
                          current_user.subscription and
                          current_user.subscription.is_active
        }
    }


@router.get("/servers")
def list_available_servers(current_user: User = Depends(get_current_user)):
    """List all available VPN servers with current metrics"""
    optimizer = get_vpn_optimizer()

    servers = []
    for server_id, server in optimizer.servers.items():
        servers.append({
            "server_id": server.server_id,
            "location": server.location,
            "latency_ms": round(server.latency_ms, 2),
            "bandwidth_mbps": round(server.bandwidth_mbps, 2),
            "cpu_load": round(server.cpu_load, 2),
            "active_connections": server.active_connections,
            "packet_loss": round(server.packet_loss, 4),
            "jitter_ms": round(server.jitter_ms, 2),
            "security_score": round(server.security_score, 3),
        })

    return {
        "total_servers": len(servers),
        "servers": servers
    }
