#!/usr/bin/env bash

# Load Hetzner API token securely
if [ -f ".env.hetzner" ]; then
    set -a
    # shellcheck source=/dev/null
    source .env.hetzner
    set +a
    echo "Hetzner API token loaded into environment."
else
    echo "Error: .env.hetzner file not found."
    exit 1
fi
