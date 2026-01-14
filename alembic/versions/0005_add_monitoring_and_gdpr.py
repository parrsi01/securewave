"""add_monitoring_and_gdpr_compliance

Revision ID: 0005
Revises: 0004
Create Date: 2024-01-07

Adds:
- Enhanced audit logs with security tracking
- Performance metrics tracking
- Uptime monitoring
- Error logs with deduplication
- GDPR compliance (data requests, consents, processing activities)
- Warrant canary for transparency
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade():
    """Add monitoring and GDPR compliance tables"""

    # ===========================
    # ENHANCE EXISTING AUDIT_LOGS TABLE
    # ===========================
    # Add new columns to existing audit_logs table
    op.add_column('audit_logs', sa.Column('event_type', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('event_category', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('actor_type', sa.String(), nullable=True))
    op.add_column('audit_logs', sa.Column('actor_email', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('resource_type', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('resource_id', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('resource_name', sa.String(), nullable=True))
    op.add_column('audit_logs', sa.Column('description', sa.Text(), nullable=True))
    op.add_column('audit_logs', sa.Column('request_id', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('severity', sa.String(), nullable=True, index=True))
    op.add_column('audit_logs', sa.Column('is_suspicious', sa.Boolean(), nullable=False, server_default='false', index=True))
    op.add_column('audit_logs', sa.Column('is_compliance_relevant', sa.Boolean(), nullable=False, server_default='true'))
    op.add_column('audit_logs', sa.Column('success', sa.Boolean(), nullable=True))
    op.add_column('audit_logs', sa.Column('error_message', sa.Text(), nullable=True))
    op.add_column('audit_logs', sa.Column('created_at', sa.DateTime(), nullable=True, index=True))

    # Create composite indexes
    op.create_index('ix_audit_user_event', 'audit_logs', ['user_id', 'event_type'])
    op.create_index('ix_audit_category_severity', 'audit_logs', ['event_category', 'severity'])
    op.create_index('ix_audit_resource', 'audit_logs', ['resource_type', 'resource_id'])
    op.create_index('ix_audit_created_category', 'audit_logs', ['created_at', 'event_category'])
    op.create_index('ix_audit_suspicious', 'audit_logs', ['is_suspicious', 'created_at'])

    # ===========================
    # PERFORMANCE METRICS TABLE
    # ===========================
    op.create_table(
        'performance_metrics',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('metric_type', sa.String(), nullable=False, index=True),
        sa.Column('endpoint', sa.String(), nullable=True, index=True),
        sa.Column('response_time_ms', sa.Integer(), nullable=True),
        sa.Column('database_time_ms', sa.Integer(), nullable=True),
        sa.Column('external_api_time_ms', sa.Integer(), nullable=True),
        sa.Column('total_time_ms', sa.Integer(), nullable=True),
        sa.Column('memory_mb', sa.Integer(), nullable=True),
        sa.Column('cpu_percent', sa.Integer(), nullable=True),
        sa.Column('request_id', sa.String(), nullable=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),
        sa.Column('status_code', sa.Integer(), nullable=True),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), index=True),
    )

    op.create_index('ix_perf_endpoint_created', 'performance_metrics', ['endpoint', 'created_at'])
    op.create_index('ix_perf_type_created', 'performance_metrics', ['metric_type', 'created_at'])

    # ===========================
    # UPTIME CHECKS TABLE
    # ===========================
    op.create_table(
        'uptime_checks',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('check_name', sa.String(), nullable=False, index=True),
        sa.Column('check_type', sa.String(), nullable=False),
        sa.Column('target', sa.String(), nullable=False),
        sa.Column('is_up', sa.Boolean(), nullable=False, index=True),
        sa.Column('response_time_ms', sa.Integer(), nullable=True),
        sa.Column('status_code', sa.Integer(), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('checked_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), index=True),
    )

    op.create_index('ix_uptime_name_checked', 'uptime_checks', ['check_name', 'checked_at'])
    op.create_index('ix_uptime_status_checked', 'uptime_checks', ['is_up', 'checked_at'])

    # ===========================
    # ERROR LOGS TABLE
    # ===========================
    op.create_table(
        'error_logs',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('error_type', sa.String(), nullable=False, index=True),
        sa.Column('error_message', sa.Text(), nullable=False),
        sa.Column('error_code', sa.String(), nullable=True, index=True),
        sa.Column('stack_trace', sa.Text(), nullable=True),
        sa.Column('file_path', sa.String(), nullable=True),
        sa.Column('line_number', sa.Integer(), nullable=True),
        sa.Column('function_name', sa.String(), nullable=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),
        sa.Column('request_id', sa.String(), nullable=True, index=True),
        sa.Column('endpoint', sa.String(), nullable=True, index=True),
        sa.Column('http_method', sa.String(), nullable=True),
        sa.Column('ip_address', sa.String(), nullable=True),
        sa.Column('user_agent', sa.String(), nullable=True),
        sa.Column('severity', sa.String(), nullable=False, index=True),
        sa.Column('occurrence_count', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('first_seen_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('last_seen_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('is_resolved', sa.Boolean(), nullable=False, server_default='false', index=True),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),
        sa.Column('resolved_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('resolution_notes', sa.Text(), nullable=True),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), index=True),
    )

    op.create_index('ix_error_type_created', 'error_logs', ['error_type', 'created_at'])
    op.create_index('ix_error_severity_resolved', 'error_logs', ['severity', 'is_resolved'])
    op.create_index('ix_error_endpoint_created', 'error_logs', ['endpoint', 'created_at'])

    # ===========================
    # GDPR REQUESTS TABLE
    # ===========================
    op.create_table(
        'gdpr_requests',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('request_number', sa.String(), unique=True, nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('request_type', sa.String(), nullable=False, index=True),  # access, erasure, etc.
        sa.Column('status', sa.String(), nullable=False, index=True, server_default='pending'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('specific_data_requested', sa.JSON(), nullable=True),
        sa.Column('assigned_to_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('processed_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('rejection_reason', sa.Text(), nullable=True),
        sa.Column('verification_method', sa.String(), nullable=True),
        sa.Column('verified_at', sa.DateTime(), nullable=True),
        sa.Column('data_export_path', sa.String(), nullable=True),
        sa.Column('data_export_format', sa.String(), nullable=True),
        sa.Column('data_export_size_bytes', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), index=True),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('due_date', sa.DateTime(), nullable=False),
        sa.Column('sla_breached', sa.Boolean(), nullable=False, server_default='false'),
    )

    # ===========================
    # USER CONSENTS TABLE
    # ===========================
    op.create_table(
        'user_consents',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('consent_type', sa.String(), nullable=False, index=True),
        sa.Column('consent_version', sa.String(), nullable=False),
        sa.Column('is_granted', sa.Boolean(), nullable=False),
        sa.Column('granted_at', sa.DateTime(), nullable=True),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
        sa.Column('ip_address', sa.String(), nullable=True),
        sa.Column('user_agent', sa.String(), nullable=True),
        sa.Column('consent_method', sa.String(), nullable=True),
        sa.Column('consent_text', sa.Text(), nullable=True),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), index=True),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # ===========================
    # DATA PROCESSING ACTIVITIES TABLE
    # ===========================
    op.create_table(
        'data_processing_activities',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('activity_name', sa.String(), nullable=False),
        sa.Column('activity_description', sa.Text(), nullable=False),
        sa.Column('purpose', sa.Text(), nullable=False),
        sa.Column('legal_basis', sa.String(), nullable=False),
        sa.Column('legal_basis_details', sa.Text(), nullable=True),
        sa.Column('data_categories', sa.JSON(), nullable=False),
        sa.Column('special_categories', sa.JSON(), nullable=True),
        sa.Column('data_subjects', sa.String(), nullable=False),
        sa.Column('data_subject_count_estimate', sa.Integer(), nullable=True),
        sa.Column('recipients', sa.JSON(), nullable=True),
        sa.Column('third_country_transfers', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('third_countries', sa.JSON(), nullable=True),
        sa.Column('transfer_safeguards', sa.Text(), nullable=True),
        sa.Column('retention_period', sa.String(), nullable=False),
        sa.Column('retention_criteria', sa.Text(), nullable=True),
        sa.Column('security_measures', sa.JSON(), nullable=False),
        sa.Column('data_controller', sa.String(), nullable=False),
        sa.Column('data_processor', sa.String(), nullable=True),
        sa.Column('dpo_contact', sa.String(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('last_reviewed_at', sa.DateTime(), nullable=True),
        sa.Column('next_review_date', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # ===========================
    # WARRANT CANARIES TABLE
    # ===========================
    op.create_table(
        'warrant_canaries',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('period_start', sa.DateTime(), nullable=False, index=True),
        sa.Column('period_end', sa.DateTime(), nullable=False, index=True),
        sa.Column('is_valid', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('statement', sa.Text(), nullable=False),
        sa.Column('signed_statement_hash', sa.String(), nullable=True),
        sa.Column('total_requests_received', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('national_security_letters', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('gag_orders', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('search_warrants', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('published_at', sa.DateTime(), nullable=False),
        sa.Column('published_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )


def downgrade():
    """Remove monitoring and GDPR compliance tables"""

    # Drop tables in reverse order
    op.drop_table('warrant_canaries')
    op.drop_table('data_processing_activities')
    op.drop_table('user_consents')
    op.drop_table('gdpr_requests')

    # Drop error logs indexes and table
    op.drop_index('ix_error_endpoint_created', 'error_logs')
    op.drop_index('ix_error_severity_resolved', 'error_logs')
    op.drop_index('ix_error_type_created', 'error_logs')
    op.drop_table('error_logs')

    # Drop uptime checks indexes and table
    op.drop_index('ix_uptime_status_checked', 'uptime_checks')
    op.drop_index('ix_uptime_name_checked', 'uptime_checks')
    op.drop_table('uptime_checks')

    # Drop performance metrics indexes and table
    op.drop_index('ix_perf_type_created', 'performance_metrics')
    op.drop_index('ix_perf_endpoint_created', 'performance_metrics')
    op.drop_table('performance_metrics')

    # Drop audit log enhancements
    op.drop_index('ix_audit_suspicious', 'audit_logs')
    op.drop_index('ix_audit_created_category', 'audit_logs')
    op.drop_index('ix_audit_resource', 'audit_logs')
    op.drop_index('ix_audit_category_severity', 'audit_logs')
    op.drop_index('ix_audit_user_event', 'audit_logs')

    op.drop_column('audit_logs', 'created_at')
    op.drop_column('audit_logs', 'error_message')
    op.drop_column('audit_logs', 'success')
    op.drop_column('audit_logs', 'is_compliance_relevant')
    op.drop_column('audit_logs', 'is_suspicious')
    op.drop_column('audit_logs', 'severity')
    op.drop_column('audit_logs', 'request_id')
    op.drop_column('audit_logs', 'description')
    op.drop_column('audit_logs', 'resource_name')
    op.drop_column('audit_logs', 'resource_id')
    op.drop_column('audit_logs', 'resource_type')
    op.drop_column('audit_logs', 'actor_email')
    op.drop_column('audit_logs', 'actor_type')
    op.drop_column('audit_logs', 'event_category')
    op.drop_column('audit_logs', 'event_type')
