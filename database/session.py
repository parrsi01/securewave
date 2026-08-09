import os
import logging
import tempfile
from typing import Generator

from sqlalchemy import create_engine, event, pool, text
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.engine import Engine
from utils.env_validation import load_environment_dotenv

# Load environment variables
load_environment_dotenv()

logger = logging.getLogger(__name__)

# Database configuration
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg2://postgres:postgres@localhost:5432/securewave",
)

# Connection pool settings (production-grade)
POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "20"))
MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", "40"))
POOL_TIMEOUT = int(os.getenv("DB_POOL_TIMEOUT", "30"))
POOL_RECYCLE = int(os.getenv("DB_POOL_RECYCLE", "3600"))  # 1 hour
POOL_PRE_PING = True

# Environment
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
IS_PRODUCTION = ENVIRONMENT == "production"

# Engine configuration
engine_config = {
    "pool_pre_ping": POOL_PRE_PING,
    # Database exceptions can otherwise include bound passwords, tokens, or
    # generated WireGuard material in framework and process-manager logs.
    "hide_parameters": True,
    # SQL echo can include bound request values.  It is opt-in even in local
    # development rather than a default source of credential leakage.
    "echo": os.getenv("SQL_ECHO", "false").lower() == "true" and not IS_PRODUCTION,
    "future": True,  # Use SQLAlchemy 2.0 style
}

# Configure based on database type
if DATABASE_URL.startswith("sqlite:///"):
    # SQLite configuration (development/testing only)
    logger.warning("Using SQLite database - NOT recommended for production!")

    # Extract the path after sqlite:///
    db_path = DATABASE_URL.replace("sqlite:///", "")

    # Ensure production SQLite uses a persistent path when explicitly selected.
    if IS_PRODUCTION:
        temp_dir = tempfile.gettempdir()
        if db_path in ("", ":memory:") or db_path.startswith(f"{temp_dir}{os.sep}"):
            db_path = os.getenv("SECUREWAVE_SQLITE_PATH", "/app/data/securewave.db")
            DATABASE_URL = f"sqlite:///{db_path}"

    # Preserve in-memory SQLite for tests/dev
    if db_path == ":memory:":
        DATABASE_URL = "sqlite:///:memory:"
    # For relative paths, use the system temp directory.
    elif not db_path.startswith("/"):
        temp_dir = tempfile.gettempdir()
        db_path = os.path.join(temp_dir, db_path)
        DATABASE_URL = f"sqlite:///{db_path}"

    # Ensure directory exists
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        try:
            os.makedirs(db_dir, exist_ok=True)
        except Exception:
            # Fallback to /tmp
            temp_dir = tempfile.gettempdir()
            DATABASE_URL = f"sqlite:///{os.path.join(temp_dir, 'securewave.db')}"
            os.makedirs(temp_dir, exist_ok=True)

    # SQLite-specific settings
    engine_config.update({
        "connect_args": {"check_same_thread": False},
        "poolclass": pool.StaticPool,  # Use static pool for SQLite
    })

    engine = create_engine(DATABASE_URL, **engine_config)

elif DATABASE_URL.startswith("postgresql"):
    # PostgreSQL configuration (production)
    logger.info("Using PostgreSQL database (production mode)")

    # PostgreSQL-specific settings
    engine_config.update({
        "pool_size": POOL_SIZE,
        "max_overflow": MAX_OVERFLOW,
        "pool_timeout": POOL_TIMEOUT,
        "pool_recycle": POOL_RECYCLE,
        "poolclass": pool.QueuePool,  # Default, but explicit
    })

    # SSL/TLS configuration for production PostgreSQL
    connect_args = {}
    if IS_PRODUCTION:
        connect_args = {
            "sslmode": os.getenv("DB_SSL_MODE", "require"),
            "connect_timeout": 10,
        }

    if connect_args:
        engine_config["connect_args"] = connect_args

    engine = create_engine(DATABASE_URL, **engine_config)

    # Log connection pool info
    logger.info("PostgreSQL connection pool configured:")
    logger.info(f"  Pool size: {POOL_SIZE}")
    logger.info(f"  Max overflow: {MAX_OVERFLOW}")
    logger.info(f"  Pool timeout: {POOL_TIMEOUT}s")
    logger.info(f"  Pool recycle: {POOL_RECYCLE}s")

else:
    # Generic database
    engine = create_engine(DATABASE_URL, **engine_config)

# Production event handlers
@event.listens_for(Engine, "connect")
def receive_connect(dbapi_conn, connection_record):
    """Event handler for new database connections"""
    logger.debug(f"New database connection established: {id(dbapi_conn)}")

    # Set PostgreSQL-specific settings for each connection
    if DATABASE_URL.startswith("postgresql"):
        cursor = dbapi_conn.cursor()
        try:
            # Set connection timezone to UTC
            cursor.execute("SET TIME ZONE 'UTC'")
            # Set statement timeout to prevent long-running queries
            cursor.execute("SET statement_timeout = '60s'")
            # Set lock timeout
            cursor.execute("SET lock_timeout = '10s'")
            cursor.close()
        except Exception as e:
            logger.warning("Failed to set connection parameters exception_type=%s", type(e).__name__)


@event.listens_for(Engine, "checkout")
def receive_checkout(dbapi_conn, connection_record, connection_proxy):
    """Event handler for connection checkout from pool"""
    logger.debug(f"Connection checked out from pool: {id(dbapi_conn)}")


@event.listens_for(Engine, "checkin")
def receive_checkin(dbapi_conn, connection_record):
    """Event handler for connection return to pool"""
    logger.debug(f"Connection returned to pool: {id(dbapi_conn)}")


# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Generator[Session, None, None]:
    """
    Database session dependency for FastAPI

    Yields:
        Session: SQLAlchemy database session

    Usage:
        @app.get("/users")
        def get_users(db: Session = Depends(get_db)):
            return db.query(User).all()
    """
    db = SessionLocal()
    try:
        yield db
    except Exception as e:
        logger.error("Database session error exception_type=%s", type(e).__name__)
        db.rollback()
        raise
    finally:
        db.close()


def create_tables():
    """Deprecated safety guard: runtime schema creation is intentionally disabled."""
    raise RuntimeError(
        "Runtime ORM schema creation is disabled. Apply Alembic migrations with `alembic upgrade head`."
    )


def check_database_connection() -> bool:
    """
    Check if database connection is working

    Returns:
        bool: True if connection is healthy, False otherwise
    """
    try:
        # Try to connect and execute a simple query
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1"))
            result.fetchone()
        logger.info("✓ Database connection is healthy")
        return True
    except Exception as e:
        logger.error("Database connection failed exception_type=%s", type(e).__name__)
        return False


def get_database_info() -> dict:
    """
    Get database connection information

    Returns:
        dict: Database information and statistics
    """
    info = {
        "url": "[redacted]",
        "driver": DATABASE_URL.split(":")[0] if ":" in DATABASE_URL else "unknown",
        "pool_size": POOL_SIZE if DATABASE_URL.startswith("postgresql") else "N/A",
        "max_overflow": MAX_OVERFLOW if DATABASE_URL.startswith("postgresql") else "N/A",
        "environment": ENVIRONMENT,
        "is_production": IS_PRODUCTION,
    }

    try:
        # Get pool statistics
        pool_obj = engine.pool
        info["pool_stats"] = {
            "size": pool_obj.size(),
            "checked_in": pool_obj.checkedin(),
            "checked_out": pool_obj.checkedout(),
            "overflow": pool_obj.overflow(),
            "total_connections": pool_obj.size() + pool_obj.overflow(),
        }
    except Exception as exc:
        logger.debug("Failed to read pool stats exception_type=%s", type(exc).__name__)

    return info


# Export commonly used items
__all__ = [
    "engine",
    "SessionLocal",
    "get_db",
    "create_tables",
    "check_database_connection",
    "get_database_info",
]
