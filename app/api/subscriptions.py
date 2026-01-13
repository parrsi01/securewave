from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.auth import get_current_user
from app.db.session import get_db
from app.models.subscription import Subscription
from app.models.user import User

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.get("/me")
def get_subscription(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    subscription = db.query(Subscription).filter(Subscription.user_id == current_user.id).first()
    if not subscription:
        return {
            "plan": "free",
            "status": "inactive",
            "current_period_end": None,
        }
    return {
        "plan": subscription.plan,
        "status": subscription.status,
        "current_period_end": subscription.current_period_end.isoformat() if subscription.current_period_end else None,
    }
