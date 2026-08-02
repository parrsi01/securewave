"""add per-user authentication token versioning

Revision ID: 0008_auth_token_version
Revises: 0007_openvpn_credentials
"""

from alembic import op
import sqlalchemy as sa


revision = "0008_auth_token_version"
down_revision = "0007_openvpn_credentials"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    user_columns = {column["name"] for column in inspector.get_columns("users")}
    if "auth_token_version" not in user_columns:
        op.add_column(
            "users",
            sa.Column(
                "auth_token_version",
                sa.Integer(),
                nullable=False,
                server_default="0",
            ),
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    user_columns = {column["name"] for column in inspector.get_columns("users")}
    if "auth_token_version" in user_columns:
        op.drop_column("users", "auth_token_version")
