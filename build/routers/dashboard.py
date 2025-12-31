from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.subscription_service import SubscriptionService

router = APIRouter()
subscription_service = SubscriptionService()


@router.get("/user")
def user_info(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "email": current_user.email,
        "subscription_status": current_user.subscription_status,
        "wg_public_key": current_user.wg_public_key,
    }


@router.get("/subscription")
def subscription(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    latest = subscription_service.get_latest_subscription(db, current_user)
    if not latest:
        return {"status": "none"}
    return {
        "provider": latest.provider,
        "status": latest.status,
        "expires_at": latest.expires_at,
    }
