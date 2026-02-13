"""add_payment_idempotency_and_webhook_receipts

Revision ID: 0009
Revises: 0008
Create Date: 2026-02-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def _has_table(bind, table_name: str) -> bool:
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _has_index(bind, table_name: str, index_name: str) -> bool:
    inspector = sa.inspect(bind)
    indexes = {idx["name"] for idx in inspector.get_indexes(table_name)}
    return index_name in indexes


def upgrade() -> None:
    bind = op.get_bind()

    if not _has_table(bind, "payment_idempotency_keys"):
        op.create_table(
            "payment_idempotency_keys",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("provider", sa.String(length=32), nullable=False),
            sa.Column("operation", sa.String(length=64), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("request_hash", sa.String(length=64), nullable=False),
            sa.Column("bucket", sa.Integer(), nullable=False),
            sa.Column("idempotency_key", sa.String(length=128), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="in_progress"),
            sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("response_json", sa.JSON(), nullable=True),
            sa.Column("last_error", sa.String(length=512), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("idempotency_key", name="uq_payment_idempotency_key"),
            sa.UniqueConstraint(
                "provider",
                "operation",
                "user_id",
                "request_hash",
                "bucket",
                name="uq_payment_idempotency_request_bucket",
            ),
        )
        op.create_index(
            "ix_payment_idempotency_user_op_time",
            "payment_idempotency_keys",
            ["user_id", "operation", "created_at"],
        )
        op.create_index(
            "ix_payment_idempotency_provider_event",
            "payment_idempotency_keys",
            ["provider", "operation", "bucket"],
        )

    if not _has_table(bind, "webhook_event_receipts"):
        op.create_table(
            "webhook_event_receipts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("provider", sa.String(length=32), nullable=False),
            sa.Column("event_id", sa.String(length=255), nullable=False),
            sa.Column("event_type", sa.String(length=128), nullable=True),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="received"),
            sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("payload_hash", sa.String(length=64), nullable=True),
            sa.Column("last_error", sa.String(length=512), nullable=True),
            sa.Column("received_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("processed_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("provider", "event_id", name="uq_webhook_provider_event"),
        )
        op.create_index(
            "ix_webhook_receipts_provider_time",
            "webhook_event_receipts",
            ["provider", "received_at"],
        )
        op.create_index(
            "ix_webhook_receipts_provider_event_type",
            "webhook_event_receipts",
            ["provider", "event_type"],
        )


def downgrade() -> None:
    bind = op.get_bind()

    if _has_table(bind, "webhook_event_receipts"):
        if _has_index(bind, "webhook_event_receipts", "ix_webhook_receipts_provider_event_type"):
            op.drop_index("ix_webhook_receipts_provider_event_type", table_name="webhook_event_receipts")
        if _has_index(bind, "webhook_event_receipts", "ix_webhook_receipts_provider_time"):
            op.drop_index("ix_webhook_receipts_provider_time", table_name="webhook_event_receipts")
        op.drop_table("webhook_event_receipts")

    if _has_table(bind, "payment_idempotency_keys"):
        if _has_index(bind, "payment_idempotency_keys", "ix_payment_idempotency_provider_event"):
            op.drop_index("ix_payment_idempotency_provider_event", table_name="payment_idempotency_keys")
        if _has_index(bind, "payment_idempotency_keys", "ix_payment_idempotency_user_op_time"):
            op.drop_index("ix_payment_idempotency_user_op_time", table_name="payment_idempotency_keys")
        op.drop_table("payment_idempotency_keys")

