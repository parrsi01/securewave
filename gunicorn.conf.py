# Gunicorn configuration file for SecureWave backend runtime
import os
import multiprocessing

# Server socket
bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
backlog = 2048

# Worker processes
workers = 1
worker_class = "uvicorn.workers.UvicornWorker"
worker_connections = 1000
timeout = 120
keepalive = 5

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"
# Do not emit request targets, referrers, or user agents here: query strings
# and headers can contain bearer credentials outside FastAPI's log filter.
access_log_format = '%(h)s %(t)s %(s)s %(b)s'

# Process naming
proc_name = "securewave-vpn"

# Server mechanics
daemon = False
pidfile = None
umask = 0
user = None
group = None
tmp_upload_dir = None

# Preload app
preload_app = False
