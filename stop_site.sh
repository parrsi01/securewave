#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="${PREVIEW_DIR:-$ROOT_DIR/.preview}"
PID_DIR="${PREVIEW_PID_DIR:-$PREVIEW_DIR/pids}"

pid_file="$PID_DIR/preview_site.pid"

if [[ ! -f "$pid_file" ]]; then
  echo "no preview pid file found ($pid_file)"
  exit 0
fi

pid="$(cat "$pid_file" || true)"
if [[ -z "${pid:-}" ]]; then
  rm -f "$pid_file"
  echo "empty pid file removed"
  exit 0
fi

if ! kill -0 "$pid" >/dev/null 2>&1; then
  rm -f "$pid_file"
  echo "process not running (pid=$pid); pid file removed"
  exit 0
fi

echo "stopping preview site (pid=$pid)"
kill "$pid" >/dev/null 2>&1 || true

for _ in $(seq 1 40); do
  if kill -0 "$pid" >/dev/null 2>&1; then
    sleep 0.25
  else
    rm -f "$pid_file"
    echo "stopped"
    exit 0
  fi
done

echo "force killing preview site (pid=$pid)"
kill -9 "$pid" >/dev/null 2>&1 || true
rm -f "$pid_file"

# Optional: stop nginx if explicitly requested (staging maintenance).
if [[ "${PREVIEW_STOP_NGINX:-0}" == "1" || "${PREVIEW_STOP_NGINX:-false}" == "true" ]]; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop nginx || true
  fi
fi
exit 0
