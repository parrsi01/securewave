"""add device lifecycle state

Revision ID: 0013
Revises: 0012
Create Date: 2026-03-12
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def _has_table(bind, table_name: str) -> bool:
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _has_column(bind, table_name: str, column_name: str) -> bool:
    inspector = sa.inspect(bind)
    cols = {column["name"] for column in inspector.get_columns(table_name)}
    return column_name in cols


def _has_index(bind, table_name: str, index_name: str) -> bool:
    inspector = sa.inspect(bind)
    indexes = {index["name"] for index in inspector.get_indexes(table_name)}
    return index_name in indexes


def upgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "wireguard_peers"):
        return

    with op.batch_alter_table("wireguard_peers") as batch:
        if not _has_column(bind, "wireguard_peers", "device_state"):
            batch.add_column(
                sa.Column(
                    "device_state",
                    sa.String(length=16),
                    nullable=False,
                    server_default="active",
                )
            )
        if not _has_column(bind, "wireguard_peers", "profile_expires_at"):
            batch.add_column(sa.Column("profile_expires_at", sa.DateTime(), nullable=True))

    if not _has_index(bind, "wireguard_peers", "ix_wireguard_peers_device_state"):
        op.create_index(
            "ix_wireguard_peers_device_state",
            "wireguard_peers",
            ["device_state"],
        )
    if not _has_index(bind, "wireguard_peers", "ix_wireguard_peers_profile_expires_at"):
        op.create_index(
            "ix_wireguard_peers_profile_expires_at",
            "wireguard_peers",
            ["profile_expires_at"],
        )

    op.execute(
        sa.text(
            """
            UPDATE wireguard_peers
            SET device_state = CASE
                WHEN is_revoked = 1 THEN 'revoked'
                WHEN is_active = 0 THEN 'expired'
                ELSE 'active'
            END
            """
        )
    )


def downgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "wireguard_peers"):
        return

    if _has_index(bind, "wireguard_peers", "ix_wireguard_peers_profile_expires_at"):
        op.drop_index("ix_wireguard_peers_profile_expires_at", table_name="wireguard_peers")
    if _has_index(bind, "wireguard_peers", "ix_wireguard_peers_device_state"):
        op.drop_index("ix_wireguard_peers_device_state", table_name="wireguard_peers")

    with op.batch_alter_table("wireguard_peers") as batch:
        if _has_column(bind, "wireguard_peers", "profile_expires_at"):
            batch.drop_column("profile_expires_at")
        if _has_column(bind, "wireguard_peers", "device_state"):
            batch.drop_column("device_state")
