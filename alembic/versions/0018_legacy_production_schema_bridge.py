"""Recognize the legacy production migration marker before reconciliation.

The original Hetzner systemd deployment advanced its private migration chain
through ``0018`` while the repository was later consolidated into the
additive ``0006``-``0008`` chain. This no-op marker lets Alembic load that
known live marker without pretending the old migration source is present.
The additive reconciliation migration still creates/backfills all current
tables and columns before the merge revision below.
"""

revision = "0018"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
