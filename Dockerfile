FROM python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py alembic.ini .env.production.example ./
COPY database/ ./database/
COPY models/ ./models/
COPY routes/ ./routes/
COPY services/ ./services/
COPY utils/ ./utils/
COPY alembic/ ./alembic/
COPY static/ ./static/
COPY scripts/docker-entrypoint.sh /usr/local/bin/securewave-entrypoint
RUN chmod 0755 /usr/local/bin/securewave-entrypoint && \
    ENVIRONMENT=testing TESTING=true DATABASE_URL=sqlite:///:memory: \
    ACCESS_TOKEN_SECRET=test-access-secret \
    python -c "import main"

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/api/health', timeout=5)"

ENTRYPOINT ["securewave-entrypoint"]
