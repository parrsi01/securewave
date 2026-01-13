from logging.config import fileConfig
from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core import config
from app.db.base import Base

from app.models.user import User  # noqa: F401
from app.models.device import Device  # noqa: F401
from app.models.subscription import Subscription  # noqa: F401
from app.models.audit_log import AuditLog  # noqa: F401
from app.models.vpn_server import VPNServer  # noqa: F401

config_section = context.config
if config_section.config_file_name is not None:
    fileConfig(config_section.config_file_name)

target_metadata = Base.metadata

def get_url():
    return config.DB_URL


def run_migrations_offline() -> None:
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    configuration = config_section.get_section(config_section.config_ini_section)
    configuration["sqlalchemy.url"] = get_url()
    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
