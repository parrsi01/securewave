# Production Dockerfile for SecureWave VPN SaaS
FROM python:3.12-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements first for layer caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend application
COPY main.py .
COPY alembic.ini .
COPY database/ ./database/
COPY models/ ./models/
COPY routers/ ./routers/
COPY services/ ./services/
COPY alembic/ ./alembic/

# Copy frontend static files
COPY frontend/ ./frontend/

# Copy nginx configuration
COPY deploy/nginx.conf /etc/nginx/nginx.conf

# Copy entrypoint script
COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create necessary directories
RUN mkdir -p /wg /app/static /var/log/nginx /var/lib/nginx

# Expose port 8080 (Azure requirement)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Run entrypoint script
CMD ["/entrypoint.sh"]
