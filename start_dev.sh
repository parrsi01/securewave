#!/bin/bash
# SecureWave VPN - Local Development Startup Script

echo "=== Starting SecureWave VPN Development Server ==="
echo ""

# Activate virtual environment
source .venv/bin/activate

# Check if database exists, create tables if needed
if [ ! -f "securewave.db" ]; then
    echo "Database not found. Creating tables..."
    python3 -c "
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print('✓ Database tables created')
"
else
    echo "✓ Database found"
fi

echo ""
echo "Starting server on http://localhost:8000"
echo "API docs available at http://localhost:8000/api/docs"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start the server
python3 main.py
