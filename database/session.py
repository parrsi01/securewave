import os
import logging
import tempfile
from typing import Generator

from sqlalchemy import create_engine, event, inspect, pool, text
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.engine import Engine

from config.settings import get_settings

logger = logging.getLogger(__name__)
SETTINGS = get_settings()

# Database configuration
DATABASE_URL = SETTINGS.database_url

# Connection pool settings (production-grade)
POOL_SIZE = SETTINGS.db_pool_size
MAX_OVERFLOW = SETTINGS.db_max_overflow
POOL_TIMEOUT = SETTINGS.db_pool_timeout
POOL_RECYCLE = SETTINGS.db_pool_recycle  # 1 hour
POOL_PRE_PING = True

# Environment
ENVIRONMENT = SETTINGS.environment
IS_PRODUCTION = SETTINGS.is_production

# Engine configuration
engine_config = {
    "pool_pre_ping": POOL_PRE_PING,
    # Disable SQL logging in production by default; override with DB_ECHO=true/false.
    "echo": SETTINGS.db_echo,
    "future": True,  # Use SQLAlchemy 2.0 style
}

# Configure based on database type
if DATABASE_URL.startswith("sqlite:///"):
    # SQLite configuration (development/testing only)
    logger.warning("Using SQLite database - NOT recommended for production!")

    # Extract the path after sqlite:///
    db_path = DATABASE_URL.replace("sqlite:///", "")

    # Ensure production SQLite uses persistent storage
    if IS_PRODUCTION:
        temp_dir = tempfile.gettempdir()
        if db_path in ("", ":memory:") or db_path.startswith(f"{temp_dir}{os.sep}"):
            db_path = "/var/lib/securewave/securewave.db"
            DATABASE_URL = f"sqlite:///{db_path}"

    # Preserve in-memory SQLite for tests/dev
    is_memory_sqlite = db_path == ":memory:"
    if is_memory_sqlite:
        DATABASE_URL = "sqlite:///:memory:"
    # For cloud: use /tmp if not absolute path
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
    })
    # StaticPool is correct for in-memory DBs. For file-backed sqlite, sharing a single
    # connection across threads can cause hard-to-debug runtime errors under ASGI load.
    engine_config["poolclass"] = pool.StaticPool if is_memory_sqlite else pool.NullPool

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

    # SSL/TLS configuration for PostgreSQL in production
    connect_args = {}
    if IS_PRODUCTION or SETTINGS.db_ssl_mode:
        connect_args = {
            "sslmode": SETTINGS.db_ssl_mode or "require",
            "connect_timeout": 10,
        }

    if connect_args:
        engine_config["connect_args"] = connect_args

    engine = create_engine(DATABASE_URL, **engine_config)

    # Log connection pool info
    logger.info(f"PostgreSQL connection pool configured:")
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
            logger.warning(f"Failed to set connection parameters: {e}")


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
        logger.error(f"Database session error: {e}")
        db.rollback()
        raise
    finally:
        db.close()


def create_tables():
    """Create all database tables"""
    from database import base
    # Import all models so SQLAlchemy registers them before metadata.create_all().
    # This is only used for non-production/dev/test environments.
    from models import (  # noqa: F401
        user,
        subscription,
        payment_idempotency_key,
        webhook_event_receipt,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
        vpn_credential,
        wireguard_peer,
        jwt_blacklist_token,
        used_totp_code,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        email_log,
        auth_refresh_token,
    )

    logger.info("Creating database tables...")
    try:
        base.Base.metadata.create_all(bind=engine)
        _ensure_sqlite_compat_columns()
        logger.info("✓ Database tables created successfully")
    except Exception as e:
        logger.error(f"Failed to create tables: {e}")
        raise


def _ensure_sqlite_compat_columns() -> None:
    """
    Backfill a small set of model columns for existing local SQLite databases.

    `create_all()` creates missing tables but does not alter old ones. Production
    uses Alembic; this keeps preview/dev SQLite databases aligned enough for
    local validation without changing the production migration path.
    """
    if not DATABASE_URL.startswith("sqlite:///"):
        return

    compat_columns = {
        "wireguard_peers": {
            "device_state": "ALTER TABLE wireguard_peers ADD COLUMN device_state VARCHAR(16) NOT NULL DEFAULT 'active'",
            "profile_expires_at": "ALTER TABLE wireguard_peers ADD COLUMN profile_expires_at DATETIME",
        },
        "vpn_servers": {
            "load_score": "ALTER TABLE vpn_servers ADD COLUMN load_score FLOAT NOT NULL DEFAULT 0.0",
        },
    }

    inspector = inspect(engine)
    with engine.begin() as conn:
        for table_name, columns in compat_columns.items():
            existing = {column["name"] for column in inspector.get_columns(table_name)}
            for column_name, ddl in columns.items():
                if column_name in existing:
                    continue
                logger.warning(
                    "SQLite compatibility migration: adding %s.%s",
                    table_name,
                    column_name,
                )
                conn.execute(text(ddl))


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
        logger.error(f"✗ Database connection failed: {e}")
        return False


def get_database_info() -> dict:
    """
    Get database connection information

    Returns:
        dict: Database information and statistics
    """
    info = {
        "url": DATABASE_URL.split("@")[-1] if "@" in DATABASE_URL else "***",  # Hide credentials
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
        logger.debug("Failed to read pool stats: %s", exc)

    return info


# Initialize database on import (development only)
if not IS_PRODUCTION and SETTINGS.auto_create_tables:
    try:
        create_tables()
    except Exception as e:
        logger.warning(f"Could not auto-create tables: {e}")


# Export commonly used items
__all__ = [
    "engine",
    "SessionLocal",
    "get_db",
    "create_tables",
    "check_database_connection",
    "get_database_info",
]
