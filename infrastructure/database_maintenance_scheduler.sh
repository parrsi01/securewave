#!/bin/bash
#
# SecureWave VPN - Database Maintenance Scheduler
# Automates weekly/monthly database maintenance tasks
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/securewave"
LOG_FILE="$LOG_DIR/database-maintenance.log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Database Maintenance Started"
log "=========================================="

cd "$PROJECT_DIR"

# Load environment
if [ -f ".env.production" ]; then
    export $(cat .env.production | grep -v '^#' | xargs)
fi

# Task 1: Run VACUUM ANALYZE
log "[1/5] Running VACUUM ANALYZE..."
python3 infrastructure/database_backup_manager.py maintenance >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "✓ VACUUM ANALYZE completed"
else
    log "✗ VACUUM ANALYZE failed"
fi

# Task 2: Update table statistics
log "[2/5] Updating table statistics..."
python3 << EOF >> "$LOG_FILE" 2>&1
from database.session import SessionLocal
db = SessionLocal()
db.execute("ANALYZE;")
db.close()
print("✓ Statistics updated")
EOF

# Task 3: Check database health
log "[3/5] Checking database health..."
python3 infrastructure/database_backup_manager.py health-check >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "✓ Health check passed"
else
    log "✗ Health check failed - manual intervention required"
fi

# Task 4: Verify backups
log "[4/5] Verifying backups..."
BACKUP_COUNT=$(python3 infrastructure/database_backup_manager.py list-backups 2>/dev/null | grep -c '"type": "automatic"' || echo "0")
log "✓ Found $BACKUP_COUNT automatic backups"

if [ "$BACKUP_COUNT" -lt 7 ]; then
    log "⚠ WARNING: Less than 7 backups available"
fi

# Task 5: Check storage usage
log "[5/5] Checking storage usage..."
python3 << EOF >> "$LOG_FILE" 2>&1
from database.session import SessionLocal
db = SessionLocal()
result = db.execute("""
    SELECT
        pg_database.datname,
        pg_size_pretty(pg_database_size(pg_database.datname)) AS size
    FROM pg_database
    WHERE datname = 'securewave_vpn'
""").fetchone()
print(f"✓ Database size: {result[1]}")
db.close()
EOF

log "=========================================="
log "Database Maintenance Completed"
log "=========================================="

# Send summary email (optional)
if command -v mail &> /dev/null; then
    SUMMARY=$(tail -20 "$LOG_FILE")
    echo "$SUMMARY" | mail -s "Database Maintenance Report - $(date '+%Y-%m-%d')" admin@securewave.app
fi

exit 0
