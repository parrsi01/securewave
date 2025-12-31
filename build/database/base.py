from sqlalchemy.orm import declarative_base

Base = declarative_base()

# Import models so Alembic picks them up
from models.user import User  # noqa: E402,F401
from models.subscription import Subscription  # noqa: E402,F401
