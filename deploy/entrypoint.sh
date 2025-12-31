#!/bin/bash
set -e

echo "[SecureWave] Starting entrypoint script..."

# Set default values
export WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"
export GUNICORN_TIMEOUT="${GUNICORN_TIMEOUT:-120}"
export WORKERS="${WEB_CONCURRENCY}"

# Run database migrations if enabled
if [ "$RUN_MIGRATIONS" = "true" ]; then
    echo "[SecureWave] Running database migrations..."
    alembic upgrade head || echo "[SecureWave] Migration failed or not needed, continuing..."
fi

# Sync static assets
echo "[SecureWave] Syncing static assets..."
if [ -d "/app/frontend" ]; then
    mkdir -p /app/static
    cp -r /app/frontend/* /app/static/ 2>/dev/null || true
    echo "[SecureWave] Static assets synced"
fi

# Start Gunicorn with Uvicorn workers in the background
echo "[SecureWave] Starting Gunicorn with Uvicorn workers..."
gunicorn main:app \
    --worker-class uvicorn.workers.UvicornWorker \
    --workers "$WORKERS" \
    --bind 127.0.0.1:8000 \
    --timeout "$GUNICORN_TIMEOUT" \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    --preload &

GUNICORN_PID=$!
echo "[SecureWave] Gunicorn started with PID $GUNICORN_PID"

# Wait for backend to be ready
echo "[SecureWave] Waiting for backend to be ready..."
sleep 5
echo "[SecureWave] Backend should be starting..."

# Start nginx in foreground
echo "[SecureWave] Starting nginx..."
exec nginx -g 'daemon off;'
