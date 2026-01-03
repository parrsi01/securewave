#!/bin/bash
# Azure App Service Startup Script - Production Ready
# NOTE: Do NOT use 'set -e' as it causes container to exit on any error

echo "=== SecureWave VPN Azure Startup ==="
echo "Timestamp: $(date)"
echo "Working Directory: $(pwd)"

# Navigate to application directory
if [ -d "/home/site/wwwroot" ]; then
    cd /home/site/wwwroot
elif [ -d "/app" ]; then
    cd /app
else
    echo "Warning: Could not find application directory, using current: $(pwd)"
fi

# Set environment variables
export PORT="${PORT:-8000}"
export PYTHONUNBUFFERED=1
export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}$(pwd)"

# Set default DATABASE_URL if not set
if [ -z "$DATABASE_URL" ]; then
    export DATABASE_URL="sqlite:////tmp/securewave.db"
    echo "DATABASE_URL not set, using: $DATABASE_URL"
fi

# Set WireGuard mock mode by default for cloud deployments
export WG_MOCK_MODE="${WG_MOCK_MODE:-true}"
export WG_DATA_DIR="${WG_DATA_DIR:-/tmp/wg_data}"

# Ensure data directories exist
mkdir -p /tmp/wg_data /tmp/data "$(pwd)/data"

echo "PORT: $PORT"
echo "DATABASE_URL: $DATABASE_URL"
echo "WG_MOCK_MODE: $WG_MOCK_MODE"
echo "Python: $(python --version 2>&1 || python3 --version 2>&1)"
echo "Current directory: $(pwd)"
echo "PYTHONPATH: $PYTHONPATH"
echo "Files present:"
ls -la | head -10

# Use python3 explicitly for Azure
PYTHON_CMD="python3"
if ! command -v python3 &> /dev/null; then
    PYTHON_CMD="python"
fi

echo "Using Python command: $PYTHON_CMD"

# Initialize database (fail-safe)
echo "Initializing database..."
$PYTHON_CMD -c "
import sys
import os
os.environ.setdefault('PYTHONPATH', os.getcwd())
try:
    from database.session import engine
    from database import base
    from models import user, subscription, audit_log, vpn_server, vpn_connection
    base.Base.metadata.create_all(bind=engine)
    print('✓ Database tables created successfully')
except Exception as e:
    print(f'⚠ Database init warning: {e}', file=sys.stderr)
    import traceback
    traceback.print_exc()
" 2>&1 || echo "⚠ Database initialization skipped"

# Initialize demo servers (fail-safe)
if [ -f "infrastructure/init_demo_servers.py" ]; then
    echo "Initializing VPN servers..."
    PYTHONPATH="$(pwd):$PYTHONPATH" $PYTHON_CMD infrastructure/init_demo_servers.py 2>&1 || echo "⚠ Server initialization skipped"
else
    echo "⚠ infrastructure/init_demo_servers.py not found, skipping"
    echo "Files in current directory:"
    find . -type f -name "*.py" | head -20
fi

echo ""
echo "========================================="
echo "Starting Gunicorn server on port $PORT"
echo "========================================="
echo ""

# Start Gunicorn with production settings
exec gunicorn main:app \
  --bind "0.0.0.0:${PORT}" \
  --workers 1 \
  --worker-class uvicorn.workers.UvicornWorker \
  --timeout 120 \
  --graceful-timeout 30 \
  --keep-alive 5 \
  --access-logfile - \
  --error-logfile - \
  --log-level debug
