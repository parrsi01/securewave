# Production Dockerfile for SecureWave VPN SaaS
FROM python:3.14-slim@sha256:a7fb1e634c4a578f9e0bd6327f11a3cde11b7a9395f48e24360c0988bcc5c2bc

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8080

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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
COPY background_tasks.py .
COPY alembic.ini .
COPY database/ ./database/
COPY infrastructure/ ./infrastructure/
COPY models/ ./models/
COPY routers/ ./routers/
COPY routes/ ./routes/
COPY services/ ./services/
COPY utils/ ./utils/
COPY alembic/ ./alembic/
COPY scripts/docker-entrypoint.sh /usr/local/bin/securewave-entrypoint

# Copy frontend static files
COPY static/ ./static/

# Create necessary directories
RUN mkdir -p /wg /app/logs

# Fail the image build if the copied runtime module set is incomplete.
RUN TESTING=true AUTO_CREATE_TABLES=false DEMO_MODE=true WG_MOCK_MODE=true \
    python -c "import main"

# Expose the application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Run migrations and replace the shell with Gunicorn for correct signal handling.
ENTRYPOINT ["securewave-entrypoint"]
