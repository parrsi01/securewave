"""
Low-stakes helper endpoints used by the website support pages.

These endpoints are intentionally simple and MUST NOT expose secrets.
"""

from fastapi import APIRouter, Request

router = APIRouter(prefix="/api/tools", tags=["tools"])


@router.get("/ip")
async def get_client_ip(request: Request):
    """Return the client IP as observed by the backend (best effort)."""
    forwarded_for = request.headers.get("x-forwarded-for", "")
    real_ip = request.headers.get("x-real-ip", "")
    # In local dev there is no proxy; request.client.host will be 127.0.0.1.
    client_ip = request.client.host if request.client else None
    ip = (real_ip or (forwarded_for.split(",")[0].strip() if forwarded_for else "") or client_ip)
    return {
        "ip": ip,
        "client": client_ip,
        "x_forwarded_for": forwarded_for,
        "x_real_ip": real_ip,
        "user_agent": request.headers.get("user-agent", ""),
    }

