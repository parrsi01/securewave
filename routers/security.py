"""
SecureWave Security Router

Exposes the SecurityMonitor capabilities as HTTP endpoints:
  GET  /api/security/status  - current threat level  (authenticated)
  GET  /api/security/alerts  - recent security alerts (admin only)
  POST /api/security/report  - report suspicious activity (authenticated)
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from models.user import User
from services.jwt_service import get_current_user
from services.security_monitor import get_security_monitor

router = APIRouter()


# ---------------------------------------------------------------------------
# Dependency: require admin
# ---------------------------------------------------------------------------

def _require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Raise 403 if the authenticated user is not an admin."""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    return current_user


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------

class SuspiciousActivityReport(BaseModel):
    """Body for POST /api/security/report."""
    category: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Category of the suspicious activity (e.g. 'phishing', 'abuse', 'unusual_traffic')",
    )
    description: str = Field(
        ...,
        min_length=5,
        max_length=2000,
        description="Human-readable description of what was observed",
    )
    details: Optional[dict] = Field(
        default=None,
        description="Optional structured details (IP addresses, timestamps, etc.)",
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/status")
def security_status(current_user: User = Depends(get_current_user)):
    """
    Return the current global threat level and high-level alert summary.
    Requires authentication.
    """
    monitor = get_security_monitor()
    summary = monitor.get_threat_summary()
    return {
        "threat_level": summary["threat_level"],
        "threat_level_updated_at": summary["threat_level_updated_at"],
        "alerts_last_hour": summary["alerts_last_hour"],
        "severity_counts": summary["severity_counts"],
    }


@router.get("/alerts")
def security_alerts(
    limit: int = 50,
    admin: User = Depends(_require_admin),
):
    """
    Return recent security alerts.  Admin-only endpoint.

    Query parameters:
      - limit: max number of alerts to return (default 50, max 200)
    """
    if limit < 1:
        limit = 1
    if limit > 200:
        limit = 200

    monitor = get_security_monitor()
    alerts = monitor.get_recent_alerts(limit=limit)
    summary = monitor.get_threat_summary()
    return {
        "threat_level": summary["threat_level"],
        "total_stored": summary["total_alerts_stored"],
        "returned": len(alerts),
        "alerts": alerts,
    }


@router.post("/report")
def report_suspicious_activity(
    body: SuspiciousActivityReport,
    current_user: User = Depends(get_current_user),
):
    """
    Submit a suspicious-activity report.  Any authenticated user may call
    this endpoint.  The report is stored as a WARNING-level security alert.
    """
    monitor = get_security_monitor()
    result = monitor.report_suspicious_activity(
        user_id=current_user.id,
        category=body.category,
        description=body.description,
        details=body.details,
    )
    return result
