#!/usr/bin/env bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  docker build -t securewave-backend -f Dockerfile .
else
  echo "Docker is not installed. Install Docker or build artifacts manually." >&2
  exit 1
fi
