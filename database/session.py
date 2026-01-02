import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Load environment variables
load_dotenv()

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg2://postgres:postgres@localhost:5432/securewave",
)

# For SQLite, ensure database is in writable location
if DATABASE_URL.startswith("sqlite:///"):
    # Azure App Service /tmp is writable
    if not DATABASE_URL.startswith("sqlite:////tmp/") and not DATABASE_URL.startswith("sqlite:////home/"):
        DATABASE_URL = "sqlite:////tmp/securewave.db"
    # Add check_same_thread=False for SQLite
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False}, pool_pre_ping=True)
else:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
