#!/usr/bin/env bash
set -euo pipefail

uvicorn main:app --reload --host "${SECUREWAVE_BACKEND_HOST:-127.0.0.1}" --port "${SECUREWAVE_BACKEND_PORT:-8001}"
