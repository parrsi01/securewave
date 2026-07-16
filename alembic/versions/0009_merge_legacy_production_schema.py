"""Merge the repository schema chain with the recognized legacy production marker."""

revision = "0009_merge_legacy_schema"
down_revision = ("0008_ikev2_credentials", "0018")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
