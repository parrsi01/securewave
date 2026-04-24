#!/usr/bin/env bash
#
# SecureWave VPN - Database Maintenance Scheduler
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${SECUREWAVE_LOG_DIR:-/var/log/securewave}"
LOG_FILE="$LOG_DIR/database-maintenance.log"
BACKUP_DIR="${SECUREWAVE_BACKUP_DIR:-/var/backups/securewave}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$PROJECT_DIR"

if [ -f ".env.production" ]; then
  set -a
  # shellcheck disable=SC1091
  source ".env.production"
  set +a
fi

log "=========================================="
log "Database Maintenance Started"
log "=========================================="

log "[1/4] Running database maintenance..."
python3 <<'PY' >> "$LOG_FILE" 2>&1
from sqlalchemy import text
from database.session import DATABASE_URL, engine

with engine.connect() as conn:
    if DATABASE_URL.startswith("postgresql"):
        conn = conn.execution_options(isolation_level="AUTOCOMMIT")
        conn.execute(text("VACUUM ANALYZE"))
        print("VACUUM ANALYZE completed")
    else:
        conn.execute(text("PRAGMA optimize"))
        print("SQLite PRAGMA optimize completed")
PY
log "Database maintenance completed"

log "[2/4] Checking database health..."
python3 <<'PY' >> "$LOG_FILE" 2>&1
from sqlalchemy import text
from database.session import engine

with engine.connect() as conn:
    conn.execute(text("SELECT 1")).fetchone()
print("Database health check passed")
PY
log "Database health check passed"

log "[3/4] Checking backup directory..."
if [ -d "$BACKUP_DIR" ]; then
  BACKUP_COUNT="$(find "$BACKUP_DIR" -type f \( -name '*.sql' -o -name '*.dump' -o -name '*.gz' \) | wc -l | tr -d ' ')"
  log "Found $BACKUP_COUNT backup files in $BACKUP_DIR"
else
  log "Backup directory not present: $BACKUP_DIR"
fi

log "[4/4] Recording database size..."
python3 <<'PY' >> "$LOG_FILE" 2>&1
from sqlalchemy import text
from database.session import DATABASE_URL, engine

with engine.connect() as conn:
    if DATABASE_URL.startswith("postgresql"):
        result = conn.execute(text("SELECT pg_size_pretty(pg_database_size(current_database()))")).fetchone()
        print(f"Database size: {result[0]}")
    else:
        print("Database size check skipped for non-PostgreSQL runtime")
PY

log "=========================================="
log "Database Maintenance Completed"
log "=========================================="
