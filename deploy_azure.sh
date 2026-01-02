#!/bin/bash
set -e

echo "Installing dependencies..."
python -m pip install --upgrade pip
pip install -r requirements.txt

echo "Setup complete"
