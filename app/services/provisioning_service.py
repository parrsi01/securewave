import logging
from typing import Optional

from sqlalchemy.orm import Session

from app.models.device import Device
from app.models.vpn_server import VPNServer

logger = logging.getLogger("app.provisioning")


def queue_peer_provisioning(
    db: Session,
    device: Device,
    server: VPNServer,
    initiated_by: Optional[int] = None,
) -> dict:
    """
    Queue a device peer provisioning task.

    TODO: Integrate real WireGuard provisioning:
      - Create/rotate peer keys
      - Push peer to VPN server (SSH/API)
      - Persist peer metadata in database
      - Trigger background worker
    """
    logger.info(
        "queued peer provisioning user_id=%s device_id=%s server_id=%s",
        initiated_by,
        device.id,
        server.server_id,
    )
    return {
        "status": "queued",
        "device_id": device.id,
        "server_id": server.server_id,
    }
