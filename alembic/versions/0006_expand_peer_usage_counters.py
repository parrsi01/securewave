"""Expand VPN peer usage counters to bigint.

Revision ID: 0006_expand_peer_usage_counters
Revises: 0005
Create Date: 2026-05-25
"""

from alembic import op
import sqlalchemy as sa


revision = "0006_expand_peer_usage_counters"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column(
        "wireguard_peers",
        "total_data_sent",
        existing_type=sa.Integer(),
        type_=sa.BigInteger(),
        existing_nullable=True,
    )
    op.alter_column(
        "wireguard_peers",
        "total_data_received",
        existing_type=sa.Integer(),
        type_=sa.BigInteger(),
        existing_nullable=True,
    )


def downgrade():
    op.alter_column(
        "wireguard_peers",
        "total_data_sent",
        existing_type=sa.BigInteger(),
        type_=sa.Integer(),
        existing_nullable=True,
    )
    op.alter_column(
        "wireguard_peers",
        "total_data_received",
        existing_type=sa.BigInteger(),
        type_=sa.Integer(),
        existing_nullable=True,
    )
