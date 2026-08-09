import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

sys.path.append(os.path.dirname(os.path.dirname(__file__)))

# Import project-local configuration only after the repository root is on the
# module path. This is required when Alembic runs from a container console
# script whose initial sys.path contains /usr/local/bin rather than /app.
from utils.env_validation import load_environment_dotenv  # noqa: E402

# Load only the selected environment's dotenv file.
load_environment_dotenv()

from database.base import Base  # noqa: E402
from database.session import DATABASE_URL  # noqa: E402

# Only the Beta 1 ORM is active. Historical tables remain represented by the
# immutable Alembic revisions above the current schema head.
from models import user, vpn_server, wireguard_peer  # noqa: E402,F401

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
