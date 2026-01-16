#!/bin/bash
###############################################################################
# SecureWave VPN - Azure App Service Startup Script (Production)
# Uses gunicorn with uvicorn workers for stability
###############################################################################

export PYTHONUNBUFFERED=1
export PORT="${PORT:-8000}"

# Use gunicorn with uvicorn workers - production stable
exec gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:$PORT --timeout 600
