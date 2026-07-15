"""Add scoped IKEv2 EAP credential lifecycle records.

Revision ID: 0008_ikev2_credentials
Revises: 0007_openvpn_credentials
Create Date: 2026-07-15
"""

from alembic import op
import sqlalchemy as sa


revision = "0008_ikev2_credentials"
down_revision = "0007_openvpn_credentials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "ikev2_credentials" in inspector.get_table_names():
        return

    op.create_table(
        "ikev2_credentials",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column(
            "device_id", sa.Integer(), sa.ForeignKey("wireguard_peers.id"), nullable=False
        ),
        sa.Column(
            "server_id", sa.Integer(), sa.ForeignKey("vpn_servers.id"), nullable=False
        ),
        sa.Column("username", sa.String(length=96), nullable=False),
        sa.Column("password_encrypted", sa.String(), nullable=False),
        sa.Column("issued_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("remote_synced_at", sa.DateTime(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("username", name="uq_ikev2_credentials_username"),
    )
    for name, columns, unique in (
        ("ix_ikev2_credentials_user_id", ["user_id"], False),
        ("ix_ikev2_credentials_device_id", ["device_id"], False),
        ("ix_ikev2_credentials_server_id", ["server_id"], False),
        ("ix_ikev2_credentials_username", ["username"], True),
        ("ix_ikev2_credentials_expires_at", ["expires_at"], False),
        ("ix_ikev2_credentials_revoked_at", ["revoked_at"], False),
        ("ix_ikev2_credentials_is_active", ["is_active"], False),
    ):
        op.create_index(name, "ikev2_credentials", columns, unique=unique)
    dialect = op.get_bind().dialect.name
    if dialect in {"sqlite", "postgresql"}:
        op.execute(
            "CREATE UNIQUE INDEX uq_ikev2_credential_active_device_server "
            "ON ikev2_credentials (user_id, device_id, server_id) "
            "WHERE revoked_at IS NULL"
        )


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "ikev2_credentials" not in inspector.get_table_names():
        return
    dialect = op.get_bind().dialect.name
    if dialect in {"sqlite", "postgresql"}:
        op.execute("DROP INDEX IF EXISTS uq_ikev2_credential_active_device_server")
    for name in (
        "ix_ikev2_credentials_is_active",
        "ix_ikev2_credentials_revoked_at",
        "ix_ikev2_credentials_expires_at",
        "ix_ikev2_credentials_username",
        "ix_ikev2_credentials_server_id",
        "ix_ikev2_credentials_device_id",
        "ix_ikev2_credentials_user_id",
    ):
        op.drop_index(name, table_name="ikev2_credentials")
    op.drop_table("ikev2_credentials")
