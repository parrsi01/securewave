"""reconcile backend API schema with runtime ORM metadata

Revision ID: 0006_backend_api_schema
Revises: 0005
Create Date: 2026-07-10

Historical SecureWave revisions were partly accompanied by runtime
``create_all`` calls.  This revision is deliberately additive and online:
it makes databases that followed either path converge without deleting data.
"""

from __future__ import annotations

import sys
from pathlib import Path

from alembic import context, op
import sqlalchemy as sa

# Alembic loads revision modules before ``env.py`` executes its project-root
# bootstrap.  Keep this revision runnable from the normal repository command
# without requiring callers to mutate PYTHONPATH.
REVISION_FILE = globals().get("__file__")
if REVISION_FILE:
    PROJECT_ROOT = Path(REVISION_FILE).resolve().parents[2]
    if str(PROJECT_ROOT) not in sys.path:
        sys.path.insert(0, str(PROJECT_ROOT))

from database.base import Base
from models import (  # noqa: F401
    audit_log,
    email_log,
    gdpr,
    invoice,
    openvpn_credential,
    subscription,
    support_ticket,
    usage_analytics,
    user,
    vpn_connection,
    vpn_demo_session,
    vpn_server,
    vpn_usage_event,
    wireguard_peer,
)


# revision identifiers, used by Alembic.
revision = "0006_backend_api_schema"
down_revision = "0005"
branch_labels = None
depends_on = None


def _column_for_add(column: sa.Column) -> sa.Column:
    """Clone a missing column without adding unsupported SQLite FKs in ALTER."""
    server_default = column.server_default
    nullable = column.nullable
    if server_default is None and not nullable:
        # Runtime defaults are Python-side for many historical fields.  Adding
        # a strict column to a populated legacy table would otherwise fail;
        # retain compatibility and let application defaults populate new rows.
        nullable = True
    return sa.Column(
        column.name,
        column.type,
        nullable=nullable,
        server_default=server_default,
    )


def _index_names(inspector: sa.Inspector, table_name: str) -> set[str]:
    names = {index["name"] for index in inspector.get_indexes(table_name) if index["name"]}
    names.update(
        constraint["name"]
        for constraint in inspector.get_unique_constraints(table_name)
        if constraint.get("name")
    )
    return names


def _assert_case_normalized_emails_are_unique(bind) -> None:
    duplicate_count = bind.execute(
        sa.text(
            "SELECT COUNT(*) FROM ("
            "SELECT lower(email) AS normalized_email FROM users "
            "GROUP BY lower(email) HAVING COUNT(*) > 1"
            ") duplicate_emails"
        )
    ).scalar_one()
    if duplicate_count:
        raise RuntimeError(
            "Cannot create case-insensitive users.email uniqueness: "
            f"{duplicate_count} duplicate normalized email group(s) require manual remediation."
        )


def upgrade():
    if context.is_offline_mode():
        raise RuntimeError(
            "0006_backend_api_schema requires an online database inspection. "
            "Run `alembic upgrade head` against the target database, not --sql."
        )

    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    # Bring all mapped tables forward.  Missing tables are created with their
    # complete FK/index definitions; existing tables receive only absent fields
    # and indexes so legacy data is retained.
    for table in Base.metadata.sorted_tables:
        if table.name not in existing_tables:
            table.create(bind=bind, checkfirst=False)
            continue

        existing_columns = {column["name"] for column in inspector.get_columns(table.name)}
        for column in table.columns:
            if column.name not in existing_columns:
                op.add_column(table.name, _column_for_add(column))

        existing_indexes = _index_names(inspector, table.name)
        for index in table.indexes:
            if table.name == "users" and index.name == "uq_users_email_lower":
                # Create this only after duplicate-case preflight below.
                continue
            if index.name and index.name not in existing_indexes:
                op.create_index(
                    index.name,
                    table.name,
                    [expression for expression in index.expressions],
                    unique=index.unique,
                )

    # Critical backfills have stable server defaults, unlike generic legacy
    # fields above.  Keeping these non-null protects token revocation and
    # metering counters on rows created before this revision.
    current_columns = {
        table_name: {column["name"] for column in sa.inspect(bind).get_columns(table_name)}
        for table_name in ("users", "wireguard_peers", "vpn_connections")
    }
    if "auth_token_version" in current_columns["users"]:
        op.execute(sa.text("UPDATE users SET auth_token_version = 0 WHERE auth_token_version IS NULL"))
    if "wg_peer_registered" in current_columns["users"]:
        users = sa.table(
            "users",
            sa.column("wg_peer_registered", sa.Boolean()),
        )
        op.execute(
            users.update()
            .where(users.c.wg_peer_registered.is_(None))
            .values(wg_peer_registered=False)
        )
    if "connection_count" in current_columns["wireguard_peers"]:
        op.execute(sa.text("UPDATE wireguard_peers SET connection_count = 0 WHERE connection_count IS NULL"))
    if "last_meter_sequence" in current_columns["vpn_connections"]:
        op.execute(sa.text("UPDATE vpn_connections SET last_meter_sequence = 0 WHERE last_meter_sequence IS NULL"))

    # `subscriptions.created_at` was nullable in 0001 but is required by the
    # current ORM. Backfill legacy rows before enforcing the invariant. Batch
    # mode keeps this portable to isolated SQLite migration tests.
    subscription_columns = {
        column["name"]: column
        for column in sa.inspect(bind).get_columns("subscriptions")
    }
    if "created_at" in subscription_columns:
        subscriptions = sa.table(
            "subscriptions",
            sa.column("created_at", sa.DateTime()),
        )
        op.execute(
            subscriptions.update()
            .where(subscriptions.c.created_at.is_(None))
            .values(created_at=sa.func.now())
        )
        if subscription_columns["created_at"].get("nullable", True):
            with op.batch_alter_table("subscriptions") as batch_op:
                batch_op.alter_column(
                    "created_at",
                    existing_type=sa.DateTime(),
                    nullable=False,
                    server_default=sa.func.now(),
                )

    inspector = sa.inspect(bind)
    user_indexes = _index_names(inspector, "users")
    if "uq_users_email_lower" not in user_indexes:
        _assert_case_normalized_emails_are_unique(bind)
        op.create_index(
            "uq_users_email_lower",
            "users",
            [sa.text("lower(email)")],
            unique=True,
        )

    connection_indexes = _index_names(sa.inspect(bind), "vpn_connections")
    if "uq_vpn_connection_active_device" not in connection_indexes:
        # PostgreSQL and SQLite both support this partial index.  It converts
        # reconnect races into a deterministic winner without limiting legacy
        # connection records that predate device attribution.
        op.execute(
            sa.text(
                "CREATE UNIQUE INDEX uq_vpn_connection_active_device "
                "ON vpn_connections (device_id) "
                "WHERE device_id IS NOT NULL AND disconnected_at IS NULL"
            )
        )


def downgrade():
    """Preserve additive compatibility data; destructive downgrade is unsafe."""
    # This revision repairs divergent production histories.  Dropping columns
    # or tables would discard audit/billing/VPN records, so downgrade is an
    # intentional no-op.  Re-upgrading is deterministic.
    pass
