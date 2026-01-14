import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context
from dotenv import load_dotenv

sys.path.append(os.path.dirname(os.path.dirname(__file__)))

# Load environment variables (production takes precedence)
load_dotenv()
load_dotenv(".env.production")

from database.base import Base  # noqa: E402
from database.session import DATABASE_URL  # noqa: E402

# Import all models to ensure they're registered with Base.metadata
from models.user import User  # noqa: E402
from models.subscription import Subscription  # noqa: E402
from models.audit_log import AuditLog  # noqa: E402
from models.vpn_server import VPNServer  # noqa: E402
from models.vpn_connection import VPNConnection  # noqa: E402

config = context.config
fileConfig(config.config_file_name)

# Set database URL from environment (production or development)
database_url = os.getenv("DATABASE_URL", DATABASE_URL)
config.set_main_option("sqlalchemy.url", database_url)


def run_migrations_offline():
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=Base.metadata, literal_binds=True)

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=Base.metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
