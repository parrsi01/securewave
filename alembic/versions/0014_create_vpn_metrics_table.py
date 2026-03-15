"""create vpn_metrics table

Revision ID: 0014
Revises: 0013
Create Date: 2026-03-12
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "vpn_metrics",
        sa.Column("id", sa.Integer, primary_key=True, index=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("device_id", sa.Integer, nullable=True),
        sa.Column("server_id", sa.String, nullable=False, index=True),
        sa.Column("handshake_time_ms", sa.Float, nullable=True),
        sa.Column("latency_ms", sa.Float, nullable=True),
        sa.Column("packet_loss_pct", sa.Float, nullable=True),
        sa.Column("throughput_mbps", sa.Float, nullable=True),
        sa.Column("protocol", sa.String, nullable=False, server_default="wireguard"),
        sa.Column("recorded_at", sa.DateTime, nullable=False, server_default=sa.func.now(), index=True),
    )
    op.create_index("ix_vpn_metrics_user_time", "vpn_metrics", ["user_id", "recorded_at"])
    op.create_index("ix_vpn_metrics_server_time", "vpn_metrics", ["server_id", "recorded_at"])


def downgrade() -> None:
    op.drop_index("ix_vpn_metrics_server_time", table_name="vpn_metrics")
    op.drop_index("ix_vpn_metrics_user_time", table_name="vpn_metrics")
    op.drop_table("vpn_metrics")
