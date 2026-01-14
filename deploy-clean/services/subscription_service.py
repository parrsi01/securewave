from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.user import User


class SubscriptionService:
    def __init__(self, default_days: int = 30):
        self.default_days = default_days

    def upsert_subscription(
        self, db: Session, user: User, provider: str, status: str, expires_at: Optional[datetime] = None
    ) -> Subscription:
        subscription = (
            db.query(Subscription)
            .filter(Subscription.user_id == user.id, Subscription.provider == provider)
            .order_by(Subscription.created_at.desc())
            .first()
        )
        if not expires_at:
            expires_at = datetime.utcnow() + timedelta(days=self.default_days)
        if subscription:
            subscription.status = status
            subscription.expires_at = expires_at
        else:
            subscription = Subscription(
                user_id=user.id,
                provider=provider,
                status=status,
                expires_at=expires_at,
            )
            db.add(subscription)
        user.subscription_status = status
        db.commit()
        db.refresh(subscription)
        return subscription

    def get_latest_subscription(self, db: Session, user: User) -> Optional[Subscription]:
        return (
            db.query(Subscription)
            .filter(Subscription.user_id == user.id)
            .order_by(Subscription.created_at.desc())
            .first()
        )
