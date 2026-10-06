"""Additive PostgreSQL migration; run against the protected deployment environment."""
from sqlalchemy import text
from database.session import engine


def migrate():
    if engine.dialect.name != "postgresql":
        raise RuntimeError("Production migration requires PostgreSQL")
    statements = [
        "SET LOCAL lock_timeout = '5s'",
        "SELECT pg_advisory_xact_lock(193720261005)",
        "ALTER TABLE vpn_connections ADD COLUMN IF NOT EXISTS metering_version INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE vpn_connections ADD COLUMN IF NOT EXISTS reporting_token_hash VARCHAR(64)",
        "ALTER TABLE vpn_connections ADD COLUMN IF NOT EXISTS recording_quality VARCHAR(16) NOT NULL DEFAULT 'legacy'",
        "ALTER TABLE vpn_connections ADD COLUMN IF NOT EXISTS client_verified_at TIMESTAMP",
        "ALTER TABLE vpn_connections ADD COLUMN IF NOT EXISTS final_meter_sequence BIGINT",
        "ALTER TABLE wireguard_peers ALTER COLUMN total_data_sent TYPE BIGINT",
        "ALTER TABLE wireguard_peers ALTER COLUMN total_data_received TYPE BIGINT",
        "ALTER TABLE wireguard_peers ADD COLUMN IF NOT EXISTS server_transfer_rx BIGINT NOT NULL DEFAULT 0",
        "ALTER TABLE wireguard_peers ADD COLUMN IF NOT EXISTS server_transfer_tx BIGINT NOT NULL DEFAULT 0",
        "ALTER TABLE wireguard_peers ADD COLUMN IF NOT EXISTS server_snapshot_at TIMESTAMP",
        "ALTER TABLE vpn_usage_events ADD COLUMN IF NOT EXISTS payload_digest VARCHAR(64)",
        "DROP INDEX IF EXISTS uq_vpn_connection_active_device",
        "CREATE UNIQUE INDEX uq_vpn_connection_active_device ON vpn_connections (device_id) WHERE device_id IS NOT NULL AND disconnected_at IS NULL AND metering_version = 1",
    ]
    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))
    print("Usage recording migration completed.")


if __name__ == "__main__":
    migrate()
