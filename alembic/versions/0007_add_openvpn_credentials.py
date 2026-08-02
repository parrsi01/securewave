"""add encrypted, per-device OpenVPN credentials

Revision ID: 0007_openvpn_credentials
Revises: 0006_backend_api_schema
Create Date: 2026-07-14
"""

from alembic import op
import sqlalchemy as sa


revision = "0007_openvpn_credentials"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "openvpn_credentials" in inspector.get_table_names():
        return
    op.create_table(
        "openvpn_credentials",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("device_id", sa.Integer(), sa.ForeignKey("wireguard_peers.id"), nullable=False),
        sa.Column("server_id", sa.Integer(), sa.ForeignKey("vpn_servers.id"), nullable=False),
        sa.Column("username", sa.String(length=96), nullable=False),
        sa.Column("password_encrypted", sa.String(), nullable=False),
        sa.Column("password_salt", sa.String(length=64), nullable=False),
        sa.Column("password_hash", sa.String(length=64), nullable=False),
        sa.Column("issued_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("remote_synced_at", sa.DateTime(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("username", name="uq_openvpn_credentials_username"),
    )
    op.create_index("ix_openvpn_credentials_user_id", "openvpn_credentials", ["user_id"])
    op.create_index("ix_openvpn_credentials_device_id", "openvpn_credentials", ["device_id"])
    op.create_index("ix_openvpn_credentials_server_id", "openvpn_credentials", ["server_id"])
    op.create_index("ix_openvpn_credentials_username", "openvpn_credentials", ["username"], unique=True)
    op.create_index("ix_openvpn_credentials_expires_at", "openvpn_credentials", ["expires_at"])
    op.create_index("ix_openvpn_credentials_revoked_at", "openvpn_credentials", ["revoked_at"])
    op.create_index("ix_openvpn_credentials_is_active", "openvpn_credentials", ["is_active"])
    op.execute(
        sa.text(
            "CREATE UNIQUE INDEX uq_openvpn_credential_active_device_server "
            "ON openvpn_credentials (user_id, device_id, server_id) "
            "WHERE revoked_at IS NULL"
        )
    )


def downgrade():
    # Credential records are security/audit material. Intentional no-op.
    pass
