#!/usr/bin/env bash
# Local PostgreSQL migration and concurrent usage-meter certification.
# Starts one disposable loopback-only container and removes it on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit

PYTHON_BIN="${PYTHON_BIN:-python3}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15@sha256:bcab099bfaab33333a73a2ebe8c1d615c9f4c2402dd43452f989a36c6da9a5ba}"
CONTAINER_NAME="securewave-postgres-cert-$PPID-$$"
POSTGRES_USER="securewave_test"
POSTGRES_DB="securewave_test"
POSTGRES_PASSWORD="local-certification-only"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "ERROR: a working Docker daemon is required." >&2
  exit 1
fi

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach --rm \
  --name "$CONTAINER_NAME" \
  --publish 127.0.0.1::5432 \
  --env "POSTGRES_USER=$POSTGRES_USER" \
  --env "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
  --env "POSTGRES_DB=$POSTGRES_DB" \
  "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "$CONTAINER_NAME" pg_isready \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" >/dev/null 2>&1; then
  echo "ERROR: disposable PostgreSQL did not become ready." >&2
  exit 1
fi

host_port="$(docker port "$CONTAINER_NAME" 5432/tcp | awk -F: 'NR == 1 {print $NF}')"
if [[ ! "$host_port" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not resolve the disposable PostgreSQL port." >&2
  exit 1
fi

database_url="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@127.0.0.1:$host_port/$POSTGRES_DB"
common_env=(
  "AUTO_CREATE_TABLES=false"
  "DATABASE_URL=$database_url"
  "SECUREWAVE_TEST_POSTGRES_URL=$database_url"
  "TESTING=true"
  "DEMO_MODE=true"
  "WG_MOCK_MODE=true"
  "ACCESS_TOKEN_SECRET=local-postgres-cert-access"
  "REFRESH_TOKEN_SECRET=local-postgres-cert-refresh"
)

reset_schema() {
  docker exec "$CONTAINER_NAME" psql \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set ON_ERROR_STOP=1 \
    --command 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;' \
    >/dev/null
}

echo "[RUN] fresh PostgreSQL migration to head"
reset_schema
env "${common_env[@]}" "$PYTHON_BIN" -m alembic upgrade head
env "${common_env[@]}" "$PYTHON_BIN" -m alembic current
env "${common_env[@]}" "$PYTHON_BIN" -m alembic upgrade head
env "${common_env[@]}" "$PYTHON_BIN" -m alembic check
echo "[PASS] fresh PostgreSQL migration to head is repeatable"

echo "[RUN] PostgreSQL upgrade from 0005 to head"
reset_schema
env "${common_env[@]}" "$PYTHON_BIN" -m alembic upgrade 0005
env "${common_env[@]}" "$PYTHON_BIN" -m alembic upgrade head
env "${common_env[@]}" "$PYTHON_BIN" -m alembic check
echo "[PASS] PostgreSQL upgrade from 0005 to head"

echo "[RUN] PostgreSQL concurrent usage idempotency"
env "${common_env[@]}" "$PYTHON_BIN" -m pytest -q \
  tests/integration/test_postgres_usage_concurrency.py
echo "[PASS] PostgreSQL concurrent usage idempotency"
