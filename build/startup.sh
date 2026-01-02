#!/bin/bash
echo "=== Starting SecureWave VPN ==="
cd /home/site/wwwroot

# Create database tables if needed
python3 -c "
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print('Database tables ready')
" || echo "Database setup skipped"

# Start server
exec gunicorn \
  -k uvicorn.workers.UvicornWorker \
  main:app \
  --bind=0.0.0.0:$PORT \
  --timeout 600 \
  --workers 2
