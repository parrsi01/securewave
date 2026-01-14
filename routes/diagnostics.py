import os
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.session import get_db
from models.audit_log import AuditLog
from services.jwt_service import get_current_user

router = APIRouter(prefix="/api/diagnostics", tags=["diagnostics"])


@router.get("/summary")
def diagnostics_summary(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    env = os.getenv("ENVIRONMENT", "development")
    demo_mode = os.getenv("DEMO_MODE", "true").lower() == "true"
    db_url = os.getenv("DATABASE_URL", "")
    db_type = "sqlite" if db_url.startswith("sqlite") else "postgres"

    return {
        "environment": env,
        "demo_mode": demo_mode,
        "database": db_type,
        "user_id": current_user.id,
    }


@router.get("/events")
def diagnostics_events(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    events = (
        db.query(AuditLog)
        .order_by(AuditLog.created_at.desc())
        .limit(20)
        .all()
    )
    return [event.to_dict() for event in events]
