#!/bin/bash
# Azure App Service Startup Script for SecureWave VPN

echo "=== SecureWave VPN Startup Script ==="
echo "Starting at: $(date)"
echo "Python: $(python --version 2>&1)"

# Navigate to app directory
cd /home/site/wwwroot

# Use PORT environment variable (Azure sets this automatically)
export PORT=${PORT:-8000}
echo "Starting on PORT: $PORT"

# Create database tables if using SQLite
echo "Initializing database..."
python -c "
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
print('Creating database tables...')
base.Base.metadata.create_all(bind=engine)
print('Database tables created successfully')
" 2>&1 || echo "Warning: Database initialization failed, continuing..."

# Start Gunicorn server (dependencies are installed by Oryx during build)
echo "Starting Gunicorn server..."
exec gunicorn -w 2 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:$PORT main:app --timeout 120 --access-logfile - --error-logfile - --log-level info
