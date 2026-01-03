#!/bin/bash
# Azure App Service Startup Script - Simplified and Robust

echo "=== SecureWave VPN Starting ==="
echo "Timestamp: $(date)"
echo "Python: $(python --version 2>&1 || python3 --version 2>&1)"
echo "Working Directory: $(pwd)"

# Set environment variables
export PYTHONUNBUFFERED=1
export PORT="${PORT:-8000}"
export DATABASE_URL="${DATABASE_URL:-sqlite:////tmp/securewave.db}"
export WG_MOCK_MODE="${WG_MOCK_MODE:-true}"
export WG_DATA_DIR="${WG_DATA_DIR:-/tmp/wg_data}"

# Ensure data directories exist
mkdir -p /tmp/wg_data /tmp/data data 2>/dev/null || true

echo "Configuration:"
echo "  PORT: $PORT"
echo "  DATABASE_URL: $DATABASE_URL"
echo "  WG_MOCK_MODE: $WG_MOCK_MODE"

# Determine Python command
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
else
    PYTHON_CMD="python"
fi

# Quick database initialization (fail-safe)
echo "Initializing database..."
$PYTHON_CMD -c "
import sys
try:
    from database.session import engine
    from database import base
    from models import user, subscription, audit_log, vpn_server, vpn_connection
    base.Base.metadata.create_all(bind=engine)
    print('✓ Database ready')
except Exception as e:
    print(f'⚠ Database init skipped: {e}', file=sys.stderr)
" 2>&1 || echo "⚠ Continuing without database init"

# Initialize demo servers (fail-safe)
if [ -f "infrastructure/init_demo_servers.py" ]; then
    echo "Initializing VPN servers..."
    $PYTHON_CMD infrastructure/init_demo_servers.py 2>&1 || echo "⚠ Server init skipped"
fi

echo ""
echo "Starting Gunicorn on port $PORT..."
echo "========================================"

# Start Gunicorn with optimized settings
exec gunicorn main:app \
  --bind "0.0.0.0:${PORT}" \
  --workers 1 \
  --worker-class uvicorn.workers.UvicornWorker \
  --timeout 120 \
  --access-logfile - \
  --error-logfile - \
  --log-level info
