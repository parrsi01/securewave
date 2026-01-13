"""add admin flag

Revision ID: 0002_admin_flag
Revises: 0001_initial
Create Date: 2024-01-01 00:00:01

"""

from alembic import op
import sqlalchemy as sa

revision = "0002_admin_flag"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.text("0")))


def downgrade() -> None:
    op.drop_column("users", "is_admin")
