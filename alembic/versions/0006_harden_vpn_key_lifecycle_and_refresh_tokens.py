"""harden_vpn_key_lifecycle_and_refresh_tokens

Revision ID: 0006
Revises: 0005
Create Date: 2026-02-12
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0006"
down_revision = "0005"
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

    if _has_table(bind, "vpn_servers"):
        with op.batch_alter_table("vpn_servers") as batch:
            if not _has_column(bind, "vpn_servers", "allowed_ips"):
                batch.add_column(
                    sa.Column(
                        "allowed_ips",
                        sa.String(),
                        nullable=False,
                        server_default="0.0.0.0/0, ::/0",
                    )
                )
            if not _has_column(bind, "vpn_servers", "wg_key_version"):
                batch.add_column(
                    sa.Column(
                        "wg_key_version",
                        sa.Integer(),
                        nullable=False,
                        server_default="1",
                    )
                )
            if not _has_column(bind, "vpn_servers", "wg_last_rotated_at"):
                batch.add_column(sa.Column("wg_last_rotated_at", sa.DateTime(), nullable=True))
            if not _has_column(bind, "vpn_servers", "wg_next_rotation_at"):
                batch.add_column(sa.Column("wg_next_rotation_at", sa.DateTime(), nullable=True))

    if not _has_table(bind, "auth_refresh_tokens"):
        op.create_table(
            "auth_refresh_tokens",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("token_jti", sa.String(length=64), nullable=False, unique=True),
            sa.Column("user_agent", sa.String(length=512), nullable=True),
            sa.Column("ip_address", sa.String(length=64), nullable=True),
            sa.Column("issued_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("replaced_by_jti", sa.String(length=64), nullable=True),
        )
        op.create_index("ix_auth_refresh_tokens_user_id", "auth_refresh_tokens", ["user_id"])
        op.create_index("ix_auth_refresh_tokens_token_jti", "auth_refresh_tokens", ["token_jti"], unique=True)
        op.create_index("ix_auth_refresh_tokens_expires_at", "auth_refresh_tokens", ["expires_at"])
        op.create_index("ix_auth_refresh_tokens_revoked_at", "auth_refresh_tokens", ["revoked_at"])
        op.create_index("ix_auth_refresh_tokens_replaced_by_jti", "auth_refresh_tokens", ["replaced_by_jti"])


def downgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "auth_refresh_tokens"):
        op.drop_index("ix_auth_refresh_tokens_replaced_by_jti", table_name="auth_refresh_tokens")
        op.drop_index("ix_auth_refresh_tokens_revoked_at", table_name="auth_refresh_tokens")
        op.drop_index("ix_auth_refresh_tokens_expires_at", table_name="auth_refresh_tokens")
        op.drop_index("ix_auth_refresh_tokens_token_jti", table_name="auth_refresh_tokens")
        op.drop_index("ix_auth_refresh_tokens_user_id", table_name="auth_refresh_tokens")
        op.drop_table("auth_refresh_tokens")

    if _has_table(bind, "vpn_servers"):
        with op.batch_alter_table("vpn_servers") as batch:
            if _has_column(bind, "vpn_servers", "wg_next_rotation_at"):
                batch.drop_column("wg_next_rotation_at")
            if _has_column(bind, "vpn_servers", "wg_last_rotated_at"):
                batch.drop_column("wg_last_rotated_at")
            if _has_column(bind, "vpn_servers", "wg_key_version"):
                batch.drop_column("wg_key_version")
            if _has_column(bind, "vpn_servers", "allowed_ips"):
                batch.drop_column("allowed_ips")
