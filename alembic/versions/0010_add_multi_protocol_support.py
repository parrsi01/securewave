"""add_multi_protocol_support

Revision ID: 0010
Revises: 0009
Create Date: 2026-02-14
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0010"
down_revision = "0009"
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
    dialect = bind.dialect.name
    true_default = sa.text("1") if dialect == "sqlite" else sa.text("true")
    false_default = sa.text("0") if dialect == "sqlite" else sa.text("false")

    if _has_table(bind, "vpn_servers"):
        # Preferred protocol for "auto" (wireguard/openvpn/ikev2/l2tp).
        if not _has_column(bind, "vpn_servers", "protocol"):
            op.add_column("vpn_servers", sa.Column("protocol", sa.String(), nullable=True))

        # Capability flags (WireGuard stays default).
        if not _has_column(bind, "vpn_servers", "supports_wireguard"):
            op.add_column(
                "vpn_servers",
                sa.Column("supports_wireguard", sa.Boolean(), nullable=False, server_default=true_default),
            )
        if not _has_column(bind, "vpn_servers", "supports_openvpn"):
            op.add_column(
                "vpn_servers",
                sa.Column("supports_openvpn", sa.Boolean(), nullable=False, server_default=false_default),
            )
        if not _has_column(bind, "vpn_servers", "supports_ikev2"):
            op.add_column(
                "vpn_servers",
                sa.Column("supports_ikev2", sa.Boolean(), nullable=False, server_default=false_default),
            )
        if not _has_column(bind, "vpn_servers", "supports_l2tp"):
            op.add_column(
                "vpn_servers",
                sa.Column("supports_l2tp", sa.Boolean(), nullable=False, server_default=false_default),
            )

        # OpenVPN configuration metadata.
        if not _has_column(bind, "vpn_servers", "openvpn_endpoint"):
            op.add_column("vpn_servers", sa.Column("openvpn_endpoint", sa.String(), nullable=True))
        if not _has_column(bind, "vpn_servers", "openvpn_port"):
            op.add_column("vpn_servers", sa.Column("openvpn_port", sa.Integer(), nullable=True, server_default="1194"))
        if not _has_column(bind, "vpn_servers", "openvpn_transport"):
            op.add_column("vpn_servers", sa.Column("openvpn_transport", sa.String(), nullable=True, server_default="udp"))
        if not _has_column(bind, "vpn_servers", "openvpn_ca_cert_pem"):
            op.add_column("vpn_servers", sa.Column("openvpn_ca_cert_pem", sa.String(), nullable=True))

        # IKEv2/IPsec metadata.
        if not _has_column(bind, "vpn_servers", "ikev2_remote_id"):
            op.add_column("vpn_servers", sa.Column("ikev2_remote_id", sa.String(), nullable=True))
        if not _has_column(bind, "vpn_servers", "ikev2_ca_cert_pem"):
            op.add_column("vpn_servers", sa.Column("ikev2_ca_cert_pem", sa.String(), nullable=True))

        # L2TP/IPsec metadata.
        if not _has_column(bind, "vpn_servers", "l2tp_psk_encrypted"):
            op.add_column("vpn_servers", sa.Column("l2tp_psk_encrypted", sa.String(), nullable=True))

    if not _has_table(bind, "vpn_credentials"):
        op.create_table(
            "vpn_credentials",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("device_id", sa.Integer(), sa.ForeignKey("wireguard_peers.id"), nullable=False),
            sa.Column("server_id", sa.Integer(), sa.ForeignKey("vpn_servers.id"), nullable=False),
            sa.Column("protocol", sa.String(length=16), nullable=False),
            sa.Column("username", sa.String(length=64), nullable=False),
            sa.Column("password_encrypted", sa.String(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint(
                "user_id",
                "device_id",
                "server_id",
                "protocol",
                name="uq_vpn_credentials_user_device_server_protocol",
            ),
        )
        op.create_index(
            "ix_vpn_credentials_user_device_protocol",
            "vpn_credentials",
            ["user_id", "device_id", "protocol"],
        )
        op.create_index(
            "ix_vpn_credentials_server_protocol",
            "vpn_credentials",
            ["server_id", "protocol"],
        )


def downgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "vpn_credentials"):
        op.drop_index("ix_vpn_credentials_server_protocol", table_name="vpn_credentials")
        op.drop_index("ix_vpn_credentials_user_device_protocol", table_name="vpn_credentials")
        op.drop_table("vpn_credentials")

    if _has_table(bind, "vpn_servers"):
        for col in (
            "l2tp_psk_encrypted",
            "ikev2_ca_cert_pem",
            "ikev2_remote_id",
            "openvpn_ca_cert_pem",
            "openvpn_transport",
            "openvpn_port",
            "openvpn_endpoint",
            "supports_l2tp",
            "supports_ikev2",
            "supports_openvpn",
            "supports_wireguard",
            "protocol",
        ):
            if _has_column(bind, "vpn_servers", col):
                op.drop_column("vpn_servers", col)
