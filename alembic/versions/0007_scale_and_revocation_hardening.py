"""scale_and_revocation_hardening

Revision ID: 0007
Revises: 0006
Create Date: 2026-02-12
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0007"
down_revision = "0006"
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
    indexes = {idx["name"] for idx in inspector.get_indexes(table_name)}
    return index_name in indexes


def upgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "wireguard_peers"):
        # Explicit unique index to guarantee fast uniqueness checks for IP allocation.
        if not _has_index(bind, "wireguard_peers", "ix_wireguard_peers_ipv4_unique"):
            op.create_index(
                "ix_wireguard_peers_ipv4_unique",
                "wireguard_peers",
                ["ipv4_address"],
                unique=True,
            )

    if not _has_table(bind, "jwt_blacklist_tokens"):
        op.create_table(
            "jwt_blacklist_tokens",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
            sa.Column("token_jti", sa.String(length=64), nullable=False, unique=True),
            sa.Column("token_type", sa.String(length=16), nullable=False),
            sa.Column("reason", sa.String(length=128), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
        )
        op.create_index("ix_jwt_blacklist_tokens_user_id", "jwt_blacklist_tokens", ["user_id"])
        op.create_index("ix_jwt_blacklist_tokens_token_jti", "jwt_blacklist_tokens", ["token_jti"], unique=True)
        op.create_index("ix_jwt_blacklist_tokens_token_type", "jwt_blacklist_tokens", ["token_type"])
        op.create_index("ix_jwt_blacklist_tokens_revoked_at", "jwt_blacklist_tokens", ["revoked_at"])
        op.create_index("ix_jwt_blacklist_tokens_expires_at", "jwt_blacklist_tokens", ["expires_at"])


def downgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "jwt_blacklist_tokens"):
        op.drop_index("ix_jwt_blacklist_tokens_expires_at", table_name="jwt_blacklist_tokens")
        op.drop_index("ix_jwt_blacklist_tokens_revoked_at", table_name="jwt_blacklist_tokens")
        op.drop_index("ix_jwt_blacklist_tokens_token_type", table_name="jwt_blacklist_tokens")
        op.drop_index("ix_jwt_blacklist_tokens_token_jti", table_name="jwt_blacklist_tokens")
        op.drop_index("ix_jwt_blacklist_tokens_user_id", table_name="jwt_blacklist_tokens")
        op.drop_table("jwt_blacklist_tokens")

    if _has_table(bind, "wireguard_peers") and _has_index(bind, "wireguard_peers", "ix_wireguard_peers_ipv4_unique"):
        op.drop_index("ix_wireguard_peers_ipv4_unique", table_name="wireguard_peers")
