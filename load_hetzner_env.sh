#!/usr/bin/env bash

# Load Hetzner API token securely
if [ -f ".env.hetzner" ]; then
    export $(grep -v '^#' .env.hetzner | xargs)
    echo "Hetzner API token loaded into environment."
else
    echo "Error: .env.hetzner file not found."
    exit 1
fi
