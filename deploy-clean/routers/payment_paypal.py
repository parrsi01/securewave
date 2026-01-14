from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.paypal_service import PayPalService
from services.subscription_service import SubscriptionService

router = APIRouter()
paypal_service = PayPalService()
subscription_service = SubscriptionService()


class PaypalOrderRequest(BaseModel):
    amount: float = 9.99


@router.post("/paypal")
@router.post("/paypal/create")
async def create_order(payload: PaypalOrderRequest, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    order = await paypal_service.create_order(payload.amount)
    if not order:
        raise HTTPException(status_code=500, detail="PayPal not configured")
    subscription_service.upsert_subscription(db, current_user, provider="paypal", status="pending")
    return order


@router.post("/paypal/capture/{order_id}")
async def capture(order_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    details = await paypal_service.capture_order(order_id)
    if not details:
        raise HTTPException(status_code=500, detail="Unable to capture PayPal order")
    subscription_service.upsert_subscription(db, current_user, provider="paypal", status="active")
    return details
