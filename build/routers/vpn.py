from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService
from services.vpn_server_service import VPNServerService
from services.audit_service import AuditService

router = APIRouter()


class VPNGenerateRequest(BaseModel):
    server_id: Optional[str] = None


class VPNDownloadRequest(BaseModel):
    server_id: Optional[str] = None


def get_wg_service(request: Request) -> WireGuardService:
    service: WireGuardService = request.app.state.wireguard
    return service


@router.post("/generate")
def generate_config(
    request: Request,
    body: VPNGenerateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Generate VPN configuration for user with optimal server selection"""
    wg_service = get_wg_service(request)
    server_service = VPNServerService()
    audit_service = AuditService()

    # Select server: use specified server_id or let optimizer choose
    if body.server_id:
        server = server_service.get_server_by_id(db, body.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")
        if server.status not in ["active", "demo"]:
            raise HTTPException(status_code=400, detail="Server not available")
    else:
        # Use optimizer to select best server
        server = server_service.allocate_server_for_user(db, current_user)
        if not server:
            raise HTTPException(status_code=503, detail="No VPN servers available")

    # Generate config for this specific server
    config_path, config_text = wg_service.generate_client_config_for_server(
        current_user,
        server
    )

    # Save user keys to database
    db.add(current_user)
    db.commit()

    # Record connection attempt
    client_ip = wg_service.allocate_ip(current_user.id).split('/')[0]
    public_ip = request.client.host if request.client else None

    connection = server_service.record_connection(
        db=db,
        user_id=current_user.id,
        server=server,
        client_ip=client_ip,
        public_ip=public_ip
    )

    # Audit log
    audit_service.log_vpn_connect(
        db=db,
        user=current_user,
        server_id=server.server_id,
        request=request,
        status="success"
    )

    return {
        "message": "WireGuard config generated",
        "config": config_text,
        "server_info": {
            "server_id": server.server_id,
            "location": server.location,
            "region": server.region,
            "public_ip": server.public_ip,
            "endpoint": server.endpoint,
            "status": server.status,
            "current_connections": server.current_connections,
        },
        "connection_id": connection.id,
    }


@router.post("/config/download")
def download_config(
    request: Request,
    body: VPNDownloadRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    wg_service = get_wg_service(request)
    if not wg_service.config_exists(current_user.id):
        wg_service.generate_client_config(current_user)
        db.add(current_user)
        db.commit()
    config_path = wg_service.users_dir / f"{current_user.id}.conf"
    return FileResponse(config_path, media_type="text/plain", filename="securewave.conf")


@router.get("/config/qr")
def qr_code(request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    wg_service = get_wg_service(request)
    if not wg_service.config_exists(current_user.id):
        wg_service.generate_client_config(current_user)
        db.add(current_user)
        db.commit()
    config_text = wg_service.get_config(current_user.id)
    qr_base64 = wg_service.qr_from_config(config_text)
    return {"qr_base64": qr_base64}


class ConnectionQualityReport(BaseModel):
    """Connection quality report from client"""
    connection_id: Optional[int] = None
    latency_ms: float
    throughput_mbps: float


@router.post("/report-quality")
def report_quality(
    quality: ConnectionQualityReport,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
):
    """Report actual connection quality for optimizer feedback"""
    from models.vpn_connection import VPNConnection
    from services.vpn_optimizer import get_vpn_optimizer

    # Get the user's active connection
    if quality.connection_id:
        connection = db.query(VPNConnection).filter(
            VPNConnection.id == quality.connection_id,
            VPNConnection.user_id == current_user.id
        ).first()
    else:
        connection = db.query(VPNConnection).filter(
            VPNConnection.user_id == current_user.id,
            VPNConnection.disconnected_at.is_(None)
        ).order_by(VPNConnection.connected_at.desc()).first()

    if not connection:
        raise HTTPException(status_code=404, detail="No active connection found")

    # Update connection record with quality metrics
    connection.avg_latency_ms = quality.latency_ms
    connection.avg_throughput_mbps = quality.throughput_mbps
    db.commit()

    # Feed to optimizer for learning
    try:
        optimizer = get_vpn_optimizer()
        server = connection.server

        optimizer.report_connection_quality(
            user_id=current_user.id,
            server_id=server.server_id,
            actual_latency=quality.latency_ms,
            actual_throughput=quality.throughput_mbps
        )
    except Exception as e:
        # Log error but don't fail the request
        import logging
        logging.getLogger(__name__).error(f"Failed to update optimizer: {e}")

    return {
        "status": "ok",
        "message": "Quality report received",
        "connection_id": connection.id
    }
