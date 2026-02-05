#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

PYTHON="${PYTHON:-}"
if [[ -z "${PYTHON}" ]]; then
  if [[ -x ".venv/bin/python" ]]; then
    PYTHON=".venv/bin/python"
  else
    PYTHON="python3"
  fi
fi

if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  echo "Python interpreter not found: ${PYTHON}" >&2
  exit 1
fi

if ! "${PYTHON}" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
  echo "Missing dependencies in ${PYTHON} environment (need fastapi + uvicorn)." >&2
  echo "Try:" >&2
  echo "  ${PYTHON} -m pip install -r requirements.txt" >&2
  exit 1
fi

base_url="http://${HOST}:${PORT}"

echo "Starting SecureWave locally at ${base_url}"

"${PYTHON}" -m uvicorn main:app --host "${HOST}" --port "${PORT}" &
server_pid="$!"

cleanup() {
  if kill -0 "${server_pid}" >/dev/null 2>&1; then
    kill "${server_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Waiting for server..."
for _ in $(seq 1 60); do
  if curl -fsS "${base_url}/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

echo ""
echo "Checks:"

home_status="$(curl -s -o /dev/null -w "%{http_code}" "${base_url}/")"
echo " - GET / -> ${home_status}"

css_status="$(curl -s -o /dev/null -w "%{http_code}" "${base_url}/css/web_ui_v1.css?v=local")"
echo " - GET /css/web_ui_v1.css -> ${css_status}"

if command -v rg >/dev/null 2>&1; then
  if curl -fsS "${base_url}/" | rg -q "UI_VERSION v1\\.0"; then
    echo " - UI_VERSION v1.0 marker -> present"
  else
    echo " - UI_VERSION v1.0 marker -> MISSING" >&2
    exit 1
  fi
else
  if curl -fsS "${base_url}/" | grep -q "UI_VERSION v1.0"; then
    echo " - UI_VERSION v1.0 marker -> present"
  else
    echo " - UI_VERSION v1.0 marker -> MISSING" >&2
    exit 1
  fi
fi

echo ""
if [[ "$(uname -s)" == "Darwin" ]]; then
  open "${base_url}/" >/dev/null 2>&1 || true
else
  echo "Open in your browser:"
  echo "  ${base_url}/"
fi

echo ""
echo "Server running (Ctrl+C to stop)..."
wait "${server_pid}"
