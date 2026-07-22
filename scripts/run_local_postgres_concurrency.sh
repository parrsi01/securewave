#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-$repo_root/.venv/bin/python}"
image='postgres:15@sha256:bcab099bfaab33333a73a2ebe8c1d615c9f4c2402dd43452f989a36c6da9a5ba'
container="securewave-cert-postgres-$$"

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required for the isolated PostgreSQL concurrency gate." >&2
  exit 2
}
[[ -x "$python_bin" ]] || {
  echo "Pinned Python environment is missing: $python_bin" >&2
  exit 2
}
docker info >/dev/null 2>&1 || {
  echo "Docker daemon access is unavailable." >&2
  exit 2
}

cleanup() {
  set +e
  if docker inspect "$container" >/dev/null 2>&1; then
    docker exec --user postgres "$container" \
      pg_ctl -D /var/lib/postgresql/data -m fast stop >/dev/null 2>&1
    docker rm "$container" >/dev/null 2>&1
  fi
}
trap cleanup EXIT INT TERM

docker run --detach --name "$container" \
  --publish 127.0.0.1::5432 \
  --env POSTGRES_USER=test_user \
  --env POSTGRES_PASSWORD=test_password \
  --env POSTGRES_DB=test_securewave \
  "$image" >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$container" pg_isready -U test_user -d test_securewave \
    >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$container" pg_isready -U test_user -d test_securewave >/dev/null

host_port="$(docker port "$container" 5432/tcp | sed -n 's/.*://p' | tail -n 1)"
[[ "$host_port" =~ ^[0-9]+$ ]] || {
  echo "Could not resolve the isolated PostgreSQL loopback port." >&2
  exit 2
}

export DATABASE_URL="postgresql://test_user:test_password@127.0.0.1:${host_port}/test_securewave"
export SECUREWAVE_TEST_POSTGRES_URL="$DATABASE_URL"
export TESTING=true AUTO_CREATE_TABLES=false DEMO_MODE=true WG_MOCK_MODE=true
export ENABLE_SENTRY=false EMAIL_VALIDATOR_CHECK_DELIVERABILITY=false BCRYPT_ROUNDS=4
export SECRET_KEY=local-certification-only
export ACCESS_TOKEN_SECRET=local-access-only
export REFRESH_TOKEN_SECRET=local-refresh-only

cd "$repo_root"
"$python_bin" - <<'PY'
import os
from sqlalchemy import create_engine, text

engine = create_engine(os.environ["DATABASE_URL"])
with engine.connect() as connection:
    connection.execute(text("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"))
    connection.commit()
print("Disposable PostgreSQL schema initialized.")
PY
"$python_bin" -m alembic upgrade head
"$python_bin" -m alembic current
"$python_bin" -m alembic check
"$python_bin" -m pytest -q tests/integration/test_postgres_usage_concurrency.py
