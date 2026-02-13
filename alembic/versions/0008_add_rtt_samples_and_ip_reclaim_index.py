"""add_rtt_samples_and_ip_reclaim_index

Revision ID: 0008
Revises: 0007
Create Date: 2026-02-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def _has_table(bind, table_name: str) -> bool:
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _has_index(bind, table_name: str, index_name: str) -> bool:
    inspector = sa.inspect(bind)
    indexes = {idx["name"] for idx in inspector.get_indexes(table_name)}
    return index_name in indexes


def upgrade() -> None:
    bind = op.get_bind()
    dialect = bind.dialect.name

    if not _has_table(bind, "vpn_server_rtt_samples"):
        op.create_table(
            "vpn_server_rtt_samples",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("vpn_server_id", sa.Integer(), sa.ForeignKey("vpn_servers.id"), nullable=False),
            sa.Column("observed_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("rtt_ms", sa.Float(), nullable=False),
            sa.Column("source", sa.String(length=64), nullable=False, server_default="health_monitor_ping"),
        )
        op.create_index(
            "ix_vpn_server_rtt_samples_server_time",
            "vpn_server_rtt_samples",
            ["vpn_server_id", "observed_at"],
        )
        op.create_index(
            "ix_vpn_server_rtt_samples_observed_at",
            "vpn_server_rtt_samples",
            ["observed_at"],
        )

    if _has_table(bind, "wireguard_peers"):
        # Replace full-unique IPv4 index with a partial unique index on active (non-revoked) peers.
        if _has_index(bind, "wireguard_peers", "ix_wireguard_peers_ipv4_unique"):
            op.drop_index("ix_wireguard_peers_ipv4_unique", table_name="wireguard_peers")

        if not _has_index(bind, "wireguard_peers", "ix_wireguard_peers_ipv4_active_unique"):
            if dialect == "sqlite":
                op.execute(
                    "CREATE UNIQUE INDEX ix_wireguard_peers_ipv4_active_unique "
                    "ON wireguard_peers (ipv4_address) WHERE is_revoked = 0"
                )
            elif dialect == "postgresql":
                op.execute(
                    "CREATE UNIQUE INDEX ix_wireguard_peers_ipv4_active_unique "
                    "ON wireguard_peers (ipv4_address) WHERE is_revoked = false"
                )
            else:
                # Best-effort fallback (may block reclaim on unsupported dialects).
                op.create_index(
                    "ix_wireguard_peers_ipv4_active_unique",
                    "wireguard_peers",
                    ["ipv4_address"],
                    unique=True,
                )


def downgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "wireguard_peers") and _has_index(bind, "wireguard_peers", "ix_wireguard_peers_ipv4_active_unique"):
        op.drop_index("ix_wireguard_peers_ipv4_active_unique", table_name="wireguard_peers")

    if _has_table(bind, "vpn_server_rtt_samples"):
        if _has_index(bind, "vpn_server_rtt_samples", "ix_vpn_server_rtt_samples_observed_at"):
            op.drop_index("ix_vpn_server_rtt_samples_observed_at", table_name="vpn_server_rtt_samples")
        if _has_index(bind, "vpn_server_rtt_samples", "ix_vpn_server_rtt_samples_server_time"):
            op.drop_index("ix_vpn_server_rtt_samples_server_time", table_name="vpn_server_rtt_samples")
        op.drop_table("vpn_server_rtt_samples")

