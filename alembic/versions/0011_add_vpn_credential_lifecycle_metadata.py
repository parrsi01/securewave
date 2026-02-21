"""add_vpn_credential_lifecycle_metadata

Revision ID: 0011
Revises: 0010
Create Date: 2026-02-21
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def _has_table(bind, table_name: str) -> bool:
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _has_column(bind, table_name: str, column_name: str) -> bool:
    inspector = sa.inspect(bind)
    cols = {col["name"] for col in inspector.get_columns(table_name)}
    return column_name in cols


def upgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "vpn_credentials"):
        return

    if not _has_column(bind, "vpn_credentials", "credential_type"):
        op.add_column(
            "vpn_credentials",
            sa.Column("credential_type", sa.String(length=32), nullable=False, server_default="username_password"),
        )

    if not _has_column(bind, "vpn_credentials", "cert_serial"):
        op.add_column("vpn_credentials", sa.Column("cert_serial", sa.String(length=128), nullable=True))
        op.create_index("ix_vpn_credentials_cert_serial", "vpn_credentials", ["cert_serial"])

    if not _has_column(bind, "vpn_credentials", "cert_fingerprint_sha256"):
        op.add_column(
            "vpn_credentials",
            sa.Column("cert_fingerprint_sha256", sa.String(length=128), nullable=True),
        )

    if not _has_column(bind, "vpn_credentials", "profile_expires_at"):
        op.add_column("vpn_credentials", sa.Column("profile_expires_at", sa.DateTime(), nullable=True))

    if not _has_column(bind, "vpn_credentials", "last_provisioned_at"):
        op.add_column("vpn_credentials", sa.Column("last_provisioned_at", sa.DateTime(), nullable=True))

    if not _has_column(bind, "vpn_credentials", "last_rotated_at"):
        op.add_column("vpn_credentials", sa.Column("last_rotated_at", sa.DateTime(), nullable=True))

    if not _has_column(bind, "vpn_credentials", "revoked_at"):
        op.add_column("vpn_credentials", sa.Column("revoked_at", sa.DateTime(), nullable=True))
        op.create_index("ix_vpn_credentials_revoked_at", "vpn_credentials", ["revoked_at"])

    if not _has_column(bind, "vpn_credentials", "revoke_reason"):
        op.add_column("vpn_credentials", sa.Column("revoke_reason", sa.String(length=128), nullable=True))

    if not _has_column(bind, "vpn_credentials", "revision"):
        op.add_column(
            "vpn_credentials",
            sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
        )

    if not _has_column(bind, "vpn_credentials", "provisioning_token_hash"):
        op.add_column(
            "vpn_credentials",
            sa.Column("provisioning_token_hash", sa.String(length=128), nullable=True),
        )

    if not _has_column(bind, "vpn_credentials", "metadata_json"):
        op.add_column("vpn_credentials", sa.Column("metadata_json", sa.JSON(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "vpn_credentials"):
        return

    if _has_column(bind, "vpn_credentials", "metadata_json"):
        op.drop_column("vpn_credentials", "metadata_json")

    if _has_column(bind, "vpn_credentials", "provisioning_token_hash"):
        op.drop_column("vpn_credentials", "provisioning_token_hash")

    if _has_column(bind, "vpn_credentials", "revision"):
        op.drop_column("vpn_credentials", "revision")

    if _has_column(bind, "vpn_credentials", "revoke_reason"):
        op.drop_column("vpn_credentials", "revoke_reason")

    if _has_column(bind, "vpn_credentials", "revoked_at"):
        op.drop_index("ix_vpn_credentials_revoked_at", table_name="vpn_credentials")
        op.drop_column("vpn_credentials", "revoked_at")

    if _has_column(bind, "vpn_credentials", "last_rotated_at"):
        op.drop_column("vpn_credentials", "last_rotated_at")

    if _has_column(bind, "vpn_credentials", "last_provisioned_at"):
        op.drop_column("vpn_credentials", "last_provisioned_at")

    if _has_column(bind, "vpn_credentials", "profile_expires_at"):
        op.drop_column("vpn_credentials", "profile_expires_at")

    if _has_column(bind, "vpn_credentials", "cert_fingerprint_sha256"):
        op.drop_column("vpn_credentials", "cert_fingerprint_sha256")

    if _has_column(bind, "vpn_credentials", "cert_serial"):
        op.drop_index("ix_vpn_credentials_cert_serial", table_name="vpn_credentials")
        op.drop_column("vpn_credentials", "cert_serial")

    if _has_column(bind, "vpn_credentials", "credential_type"):
        op.drop_column("vpn_credentials", "credential_type")
