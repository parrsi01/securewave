"""add used_totp_codes table for TOTP replay prevention

Revision ID: 0016
Revises: 0015
Create Date: 2026-03-18
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "used_totp_codes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True, nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(6), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_used_totp_codes_user_id", "used_totp_codes", ["user_id"])
    op.create_index(
        "ix_used_totp_codes_user_code_time",
        "used_totp_codes",
        ["user_id", "code", "used_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_used_totp_codes_user_code_time", table_name="used_totp_codes")
    op.drop_index("ix_used_totp_codes_user_id", table_name="used_totp_codes")
    op.drop_table("used_totp_codes")
