#!/bin/bash
###############################################################################
# SecureWave VPN - Azure App Service Startup Script (Simplified)
###############################################################################

echo "SecureWave VPN - Starting..."
echo "Timestamp: $(date)"

# Activate Azure's virtual environment (created by Oryx)
if [ -d "/home/site/wwwroot/antenv" ]; then
    source /home/site/wwwroot/antenv/bin/activate
fi

# Set environment variables
export PYTHONUNBUFFERED=1
export PORT="${PORT:-8000}"

echo "Starting Uvicorn on port $PORT..."

# Start Uvicorn directly - simple and fast
exec python -m uvicorn main:app --host 0.0.0.0 --port $PORT
