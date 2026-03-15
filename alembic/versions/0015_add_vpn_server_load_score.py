"""add load_score column to vpn_servers

Revision ID: 0015
Revises: 0014
Create Date: 2026-03-14
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "vpn_servers",
        sa.Column("load_score", sa.Float(), nullable=False, server_default="0.0"),
    )


def downgrade() -> None:
    op.drop_column("vpn_servers", "load_score")
