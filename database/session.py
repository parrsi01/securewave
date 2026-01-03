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
    # Extract the path after sqlite:///
    db_path = DATABASE_URL.replace("sqlite:///", "")

    # For Azure/Cloud: use /tmp if not absolute path
    if not db_path.startswith("/"):
        db_path = f"/tmp/{db_path}"
        DATABASE_URL = f"sqlite:///{db_path}"

    # Ensure directory exists
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        try:
            os.makedirs(db_dir, exist_ok=True)
        except Exception:
            # Fallback to /tmp
            DATABASE_URL = "sqlite:////tmp/securewave.db"
            os.makedirs("/tmp", exist_ok=True)

    # Add check_same_thread=False for SQLite
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
        echo=os.getenv("ENVIRONMENT") != "production"
    )
else:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
