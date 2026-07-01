"""
User-facing account endpoints used by the native apps.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.usage_metering import plan_payload

router = APIRouter(prefix="/api/user", tags=["user"])


@router.get("/plan")
async def get_user_plan(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return the user's current plan and usage summary.

    Response shape matches the Flutter app's `UserPlan.fromJson`.
    """
    return plan_payload(db, current_user)
