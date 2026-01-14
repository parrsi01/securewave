from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.stripe_service import StripeService
from services.subscription_service import SubscriptionService

router = APIRouter()
stripe_service = StripeService()
subscription_service = SubscriptionService()


@router.post("/stripe")
def create_checkout(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    url = stripe_service.create_checkout_session(current_user.email)
    if not url:
        raise HTTPException(status_code=500, detail="Stripe not configured")
    subscription_service.upsert_subscription(db, current_user, provider="stripe", status="pending")
    return {"checkout_url": url}
