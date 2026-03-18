"""
Low-stakes helper endpoints used by the website support pages.

These endpoints are intentionally simple and MUST NOT expose secrets.
"""

from fastapi import APIRouter, Request

router = APIRouter(prefix="/api/tools", tags=["tools"])


@router.get("/ip")
async def get_client_ip(request: Request):
    """Return the client IP as observed by the backend (best effort).
    Only the first (client-facing) IP is returned — the full XFF chain is not exposed.
    """
    forwarded_for = request.headers.get("x-forwarded-for", "")
    real_ip = request.headers.get("x-real-ip", "")
    # In local dev there is no proxy; request.client.host will be 127.0.0.1.
    client_ip = request.client.host if request.client else None
    # Use only the first entry of XFF (client IP); strip proxy chain to prevent info leak.
    xff_client_ip = forwarded_for.split(",")[0].strip() if forwarded_for else ""
    ip = real_ip or xff_client_ip or client_ip
    return {"ip": ip}

