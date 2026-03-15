"""add vpn server region selection columns

Revision ID: 0012
Revises: 0011
Create Date: 2026-03-09
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def _has_table(bind, table_name: str) -> bool:
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _has_column(bind, table_name: str, column_name: str) -> bool:
    inspector = sa.inspect(bind)
    cols = {column["name"] for column in inspector.get_columns(table_name)}
    return column_name in cols


def upgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "vpn_servers"):
        return

    with op.batch_alter_table("vpn_servers") as batch:
        if not _has_column(bind, "vpn_servers", "region_group"):
            batch.add_column(sa.Column("region_group", sa.String(), nullable=True))
        if not _has_column(bind, "vpn_servers", "is_primary_region"):
            batch.add_column(
                sa.Column("is_primary_region", sa.Boolean(), nullable=False, server_default=sa.false())
            )
        if not _has_column(bind, "vpn_servers", "priority_weight"):
            batch.add_column(
                sa.Column("priority_weight", sa.Integer(), nullable=False, server_default="100")
            )
        if not _has_column(bind, "vpn_servers", "latency_score"):
            batch.add_column(sa.Column("latency_score", sa.Float(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "vpn_servers"):
        return

    with op.batch_alter_table("vpn_servers") as batch:
        if _has_column(bind, "vpn_servers", "latency_score"):
            batch.drop_column("latency_score")
        if _has_column(bind, "vpn_servers", "priority_weight"):
            batch.drop_column("priority_weight")
        if _has_column(bind, "vpn_servers", "is_primary_region"):
            batch.drop_column("is_primary_region")
        if _has_column(bind, "vpn_servers", "region_group"):
            batch.drop_column("region_group")
