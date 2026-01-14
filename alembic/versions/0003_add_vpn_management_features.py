"""add_vpn_management_and_support_features

Revision ID: 0003
Revises: 0002
Create Date: 2024-01-07

Adds:
- WireGuard peer management
- Support ticket system
- Usage analytics
- Abuse detection logs
- System metrics
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    """Add VPN management and support features"""

    # ===========================
    # WIREGUARD PEERS TABLE
    # ===========================
    op.create_table(
        'wireguard_peers',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('server_id', sa.Integer(), sa.ForeignKey('vpn_servers.id'), nullable=True, index=True),
        sa.Column('public_key', sa.String(), nullable=False, unique=True, index=True),
        sa.Column('private_key_encrypted', sa.String(), nullable=False),
        sa.Column('ipv4_address', sa.String(), nullable=False),
        sa.Column('ipv6_address', sa.String(), nullable=True),
        sa.Column('device_name', sa.String(), nullable=True),
        sa.Column('device_type', sa.String(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('is_revoked', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('key_version', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('last_key_rotation_at', sa.DateTime(), nullable=True),
        sa.Column('next_key_rotation_at', sa.DateTime(), nullable=True),
        sa.Column('last_handshake_at', sa.DateTime(), nullable=True),
        sa.Column('total_data_sent', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_data_received', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
    )
    op.create_index('ix_peer_user_server', 'wireguard_peers', ['user_id', 'server_id'])

    # ===========================
    # SUPPORT TICKETS TABLE
    # ===========================
    op.create_table(
        'support_tickets',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('ticket_number', sa.String(), nullable=False, unique=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('assigned_to_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('subject', sa.String(200), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('category', sa.String(), nullable=False, index=True, server_default='other'),
        sa.Column('priority', sa.String(), nullable=False, index=True, server_default='medium'),
        sa.Column('status', sa.String(), nullable=False, index=True, server_default='open'),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('tags', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, index=True, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('first_response_at', sa.DateTime(), nullable=True),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),
        sa.Column('closed_at', sa.DateTime(), nullable=True),
        sa.Column('sla_due_at', sa.DateTime(), nullable=True),
        sa.Column('sla_breached', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('user_rating', sa.Integer(), nullable=True),
        sa.Column('user_feedback', sa.Text(), nullable=True),
    )

    # ===========================
    # TICKET MESSAGES TABLE
    # ===========================
    op.create_table(
        'ticket_messages',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('ticket_id', sa.Integer(), sa.ForeignKey('support_tickets.id'), nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('is_internal', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('is_automated', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('attachments', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # ===========================
    # USER USAGE STATS TABLE
    # ===========================
    op.create_table(
        'user_usage_stats',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, unique=True, index=True),
        sa.Column('total_connections', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_connections', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_connection_time_seconds', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('average_session_duration_seconds', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_connection_at', sa.DateTime(), nullable=True),
        sa.Column('total_bytes_uploaded', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('total_bytes_downloaded', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('total_data_gb', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('current_month_data_gb', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('favorite_server_id', sa.String(), nullable=True),
        sa.Column('unique_servers_used', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_server_switches', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('average_latency_ms', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('average_throughput_mbps', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('connection_failure_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('connection_success_rate', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('total_login_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('failed_login_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_login_at', sa.DateTime(), nullable=True),
        sa.Column('account_age_days', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_subscription_renewals', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('subscription_lifetime_value', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('current_subscription_tier', sa.String(), nullable=True),
        sa.Column('total_support_tickets', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('open_support_tickets', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('average_ticket_resolution_hours', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('first_seen_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('last_activity_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # ===========================
    # DAILY USAGE METRICS TABLE
    # ===========================
    op.create_table(
        'daily_usage_metrics',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('date', sa.DateTime(), nullable=False, index=True),
        sa.Column('connections_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_connection_time_seconds', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('data_uploaded_mb', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('data_downloaded_mb', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('total_data_mb', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('avg_latency_ms', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('avg_throughput_mbps', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('connection_failures', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('servers_used', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_daily_usage_user_date', 'daily_usage_metrics', ['user_id', 'date'])

    # ===========================
    # ABUSE DETECTION LOGS TABLE
    # ===========================
    op.create_table(
        'abuse_detection_logs',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('incident_type', sa.String(), nullable=False, index=True),
        sa.Column('severity', sa.String(), nullable=False, index=True),
        sa.Column('description', sa.String(), nullable=False),
        sa.Column('metadata', sa.JSON(), nullable=True),
        sa.Column('detection_method', sa.String(), nullable=True),
        sa.Column('detected_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('action_taken', sa.String(), nullable=True),
        sa.Column('action_notes', sa.String(), nullable=True),
        sa.Column('action_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('status', sa.String(), nullable=False, index=True, server_default='pending'),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),
        sa.Column('detected_at', sa.DateTime(), nullable=False, index=True, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # ===========================
    # SYSTEM METRICS TABLE
    # ===========================
    op.create_table(
        'system_metrics',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('timestamp', sa.DateTime(), nullable=False, index=True, server_default=sa.func.now()),
        sa.Column('total_users', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_users_24h', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_users_7d', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_users_30d', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('new_users_today', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_connections', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_connections', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('average_session_duration_minutes', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('total_servers', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('healthy_servers', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('degraded_servers', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('offline_servers', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('average_server_load', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('total_bandwidth_gb_24h', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('average_throughput_mbps', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('peak_bandwidth_mbps', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('average_latency_ms', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('average_packet_loss', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('connection_success_rate', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('total_subscriptions', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('active_subscriptions', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('mrr', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('churn_rate', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('open_tickets', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('tickets_resolved_24h', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('average_resolution_time_hours', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('abuse_incidents_24h', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('failed_logins_24h', sa.Integer(), nullable=False, server_default='0'),
    )


def downgrade():
    """Remove VPN management and support features"""

    # Drop tables in reverse order
    op.drop_table('system_metrics')
    op.drop_table('abuse_detection_logs')
    op.drop_index('ix_daily_usage_user_date', 'daily_usage_metrics')
    op.drop_table('daily_usage_metrics')
    op.drop_table('user_usage_stats')
    op.drop_table('ticket_messages')
    op.drop_table('support_tickets')
    op.drop_index('ix_peer_user_server', 'wireguard_peers')
    op.drop_table('wireguard_peers')
