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
# Alembic owns schema creation and migration. Prevent the development-only
# database import hook from creating model tables before revision 0001 runs.
os.environ["AUTO_CREATE_TABLES"] = "false"
from database.session import DATABASE_URL  # noqa: E402

# Import every model module so all tables are registered with Base.metadata.
from models import (  # noqa: E402,F401
    audit_log,
    email_log,
    gdpr,
    invoice,
    subscription,
    support_ticket,
    usage_analytics,
    user,
    vpn_connection,
    vpn_demo_session,
    vpn_server,
    wireguard_peer,
)

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
