#!/bin/bash
# Quick health check script for SecureWave VPN

echo "🏥 SecureWave VPN Health Check"
echo "================================"
echo ""

# Check if running locally
if curl -sf http://localhost:8000/api/health > /dev/null 2>&1; then
    echo "✅ Local server is running"
    echo "   URL: http://localhost:8000"
    curl -s http://localhost:8000/api/health | python3 -m json.tool 2>/dev/null || echo ""
else
    echo "❌ Local server is not running"
    echo "   Start with: bash deploy.sh local"
fi

echo ""
echo "--------------------------------"
echo ""

# Check if running on Azure
if curl -sf https://securewave-web.azurewebsites.net/api/health > /dev/null 2>&1; then
    echo "✅ Azure deployment is running"
    echo "   URL: https://securewave-web.azurewebsites.net"
    curl -s https://securewave-web.azurewebsites.net/api/health | python3 -m json.tool 2>/dev/null || echo ""
else
    echo "❌ Azure deployment is not responding"
    echo "   Deploy with: bash deploy.sh azure"
    echo "   Or check status: bash deploy.sh diagnostics"
fi

echo ""
echo "================================"
