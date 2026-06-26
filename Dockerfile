# Production Dockerfile for SecureWave VPN SaaS
FROM python:3.12-slim

ARG APP_VERSION=dev
ARG GIT_SHA=unknown

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PORT=8080

# Install runtime and wheel-build dependencies. Some pinned packages do not
# publish wheels for every Python/architecture combination.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements first for layer caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt \
    && apt-get purge -y --auto-remove gcc python3-dev

# Copy backend application. Keep this list explicit so the production image
# fails code review when a new runtime package is introduced.
COPY main.py .
COPY background_tasks.py .
COPY gunicorn.conf.py .
COPY alembic.ini .
COPY config/ ./config/
COPY database/ ./database/
COPY data/models/ ./data/models/
COPY infrastructure/ ./infrastructure/
COPY ml/ ./ml/
COPY models/ ./models/
COPY routers/ ./routers/
COPY routes/ ./routes/
COPY scripts/docker_entrypoint.sh ./scripts/docker_entrypoint.sh
COPY services/ ./services/
COPY utils/ ./utils/
COPY alembic/ ./alembic/

# Copy frontend static files
COPY static/ ./static/

# Create necessary directories
RUN useradd --create-home --shell /usr/sbin/nologin securewave \
    && mkdir -p /wg /app/logs /app/data \
    && chmod +x /app/scripts/docker_entrypoint.sh \
    && chown -R securewave:securewave /app /wg

USER securewave

# Expose the application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Run migrations and start Gunicorn
ENTRYPOINT ["/app/scripts/docker_entrypoint.sh"]
