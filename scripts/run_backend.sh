#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_NETOPSD_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/securewave/netops.sock"

export SECUREWAVE_NETOPSD_ENABLED="${SECUREWAVE_NETOPSD_ENABLED:-true}"
export SECUREWAVE_NETOPSD_REQUIRED="${SECUREWAVE_NETOPSD_REQUIRED:-true}"
export SECUREWAVE_NETOPSD_SOCKET_PATH="${SECUREWAVE_NETOPSD_SOCKET_PATH:-$DEFAULT_NETOPSD_SOCKET}"
export PYTHONPATH="${ROOT_DIR}:${PYTHONPATH:-}"

uvicorn main:app --reload --host 0.0.0.0 --port 8000
