#!/bin/bash
set -e  # Exit on any error
# Simple Azure deployment script
echo "Deploying SecureWave VPN to Azure..."

# Install Python dependencies
if [ -f "requirements.txt" ]; then
    echo "Installing dependencies..."
    python3 -m pip install --upgrade pip
    python3 -m pip install -r requirements.txt
fi

echo "Deployment complete!"
