"""reconcile runtime tables and model columns

Revision ID: 0006
Revises: 0005
"""

from alembic import op
import sqlalchemy as sa


revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def _load_model_metadata():
    from database.base import Base
    from models import (
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

    # Imports above register every model with the shared metadata object.
    return Base.metadata


def upgrade():
    """Bring an Alembic-created database up to the current model contract."""
    bind = op.get_bind()
    metadata = _load_model_metadata()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    # The historical chain created several feature tables but omitted the
    # runtime tables used by the production API. Create any absent model table
    # using its canonical SQLAlchemy definition.
    for table in metadata.sorted_tables:
        if table.name not in existing_tables:
            table.create(bind=bind)
            existing_tables.add(table.name)

    # Earlier revisions created a partial users/subscriptions/audit schema.
    # Add model columns without rewriting populated tables. New columns are
    # nullable here so existing installations can upgrade without data loss;
    # application defaults continue to apply on new ORM writes.
    for table in metadata.sorted_tables:
        if table.name not in existing_tables:
            continue
        existing_columns = {
            column["name"] for column in sa.inspect(bind).get_columns(table.name)
        }
        for model_column in table.columns:
            if model_column.name in existing_columns:
                continue
            op.add_column(
                table.name,
                sa.Column(model_column.name, model_column.type, nullable=True),
            )
            existing_columns.add(model_column.name)

    # 0003 had to omit this FK so its historical order could run on a clean
    # database. Restore the declared relationship after vpn_servers exists.
    inspector = sa.inspect(bind)
    if "wireguard_peers" in inspector.get_table_names():
        has_server_fk = any(
            foreign_key.get("referred_table") == "vpn_servers"
            and foreign_key.get("constrained_columns") == ["server_id"]
            for foreign_key in inspector.get_foreign_keys("wireguard_peers")
        )
        if not has_server_fk:
            with op.batch_alter_table("wireguard_peers") as batch:
                batch.create_foreign_key(
                    "fk_wireguard_peers_server_id_vpn_servers",
                    "vpn_servers",
                    ["server_id"],
                    ["id"],
                )


def downgrade():
    """Do not remove runtime tables or model columns during a rollback."""
    # This revision repairs an incomplete historical schema. Removing the
    # repaired tables would reintroduce the production startup failure.
    pass
