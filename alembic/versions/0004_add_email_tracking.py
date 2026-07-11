"""add_email_tracking_and_templates

Revision ID: 0004
Revises: 0003
Create Date: 2024-01-07

Adds:
- Email logs for tracking sent emails
- Email templates for standardized communications
- Email engagement tracking (opens, clicks, bounces)
"""
from alembic import context, op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    if context.is_offline_mode():
        return False
    return table_name in set(sa.inspect(op.get_bind()).get_table_names())


def _create_table_if_missing(table_name: str, *columns) -> None:
    if not _table_exists(table_name):
        op.create_table(table_name, *columns)


def _create_index_if_missing(index_name: str, table_name: str, columns) -> None:
    if context.is_offline_mode() or not _table_exists(table_name):
        op.create_index(index_name, table_name, columns)
        return
    indexes = {index["name"] for index in sa.inspect(op.get_bind()).get_indexes(table_name)}
    if index_name not in indexes:
        op.create_index(index_name, table_name, columns)


def upgrade():
    """Add email tracking and template tables"""

    # ===========================
    # EMAIL LOGS TABLE
    # ===========================
    _create_table_if_missing(
        'email_logs',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),

        # Email details
        sa.Column('to_email', sa.String(), nullable=False, index=True),
        sa.Column('from_email', sa.String(), nullable=False),
        sa.Column('subject', sa.String(), nullable=False),
        sa.Column('template_name', sa.String(), nullable=True, index=True),

        # Email categorization
        sa.Column('email_type', sa.String(), nullable=False, index=True),  # transactional, marketing, notification, system
        sa.Column('category', sa.String(), nullable=True),  # billing, support, vpn, account

        # Provider information
        sa.Column('provider', sa.String(), nullable=False),  # smtp, sendgrid, aws_ses
        sa.Column('provider_message_id', sa.String(), nullable=True),

        # Status tracking
        sa.Column('status', sa.String(), nullable=False, index=True),  # queued, sent, delivered, failed, bounced, opened, clicked
        sa.Column('error_message', sa.Text(), nullable=True),

        # Metadata
        sa.Column('metadata', sa.JSON(), nullable=True),

        # Engagement tracking timestamps
        sa.Column('sent_at', sa.DateTime(), nullable=True),
        sa.Column('delivered_at', sa.DateTime(), nullable=True),
        sa.Column('opened_at', sa.DateTime(), nullable=True),
        sa.Column('clicked_at', sa.DateTime(), nullable=True),
        sa.Column('bounced_at', sa.DateTime(), nullable=True),
        sa.Column('failed_at', sa.DateTime(), nullable=True),

        # Record timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False, index=True, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # Create composite indexes for common queries
    _create_index_if_missing('ix_email_logs_user_status', 'email_logs', ['user_id', 'status'])
    _create_index_if_missing('ix_email_logs_template_status', 'email_logs', ['template_name', 'status'])
    _create_index_if_missing('ix_email_logs_created_status', 'email_logs', ['created_at', 'status'])

    # ===========================
    # EMAIL TEMPLATES TABLE
    # ===========================
    _create_table_if_missing(
        'email_templates',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(), unique=True, nullable=False, index=True),
        sa.Column('subject', sa.String(), nullable=False),
        sa.Column('html_template', sa.Text(), nullable=False),
        sa.Column('text_template', sa.Text(), nullable=True),

        # Template metadata
        sa.Column('description', sa.String(), nullable=True),
        sa.Column('category', sa.String(), nullable=True),  # account, billing, support, vpn
        sa.Column('variables', sa.JSON(), nullable=True),  # List of template variables

        # Status
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),

        # Timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # Create index for active templates by category
    _create_index_if_missing('ix_email_templates_category_active', 'email_templates', ['category', 'is_active'])


def downgrade():
    """Remove email tracking and template tables"""

    # Drop indexes
    op.drop_index('ix_email_templates_category_active', 'email_templates')
    op.drop_index('ix_email_logs_created_status', 'email_logs')
    op.drop_index('ix_email_logs_template_status', 'email_logs')
    op.drop_index('ix_email_logs_user_status', 'email_logs')

    # Drop tables
    op.drop_table('email_templates')
    op.drop_table('email_logs')
