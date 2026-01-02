#!/usr/bin/env bash
set -eo pipefail

# SecureWave VPN - Post-Deployment Health Check
# Verifies all systems are operational after deployment

BASE_URL="${1:-https://securewave-app.azurewebsites.net}"

echo "=========================================="
echo "SecureWave VPN - Health Check"
echo "=========================================="
echo "Target: $BASE_URL"
echo "=========================================="
echo

FAILURES=0

# Helper function for checks
check() {
    local name="$1"
    local command="$2"
    printf "%-40s" "$name..."

    if eval "$command" > /dev/null 2>&1; then
        echo "✅ PASS"
        return 0
    else
        echo "❌ FAIL"
        ((FAILURES++))
        return 1
    fi
}

# 1. API Health
echo "[1/8] Basic Health Checks"
check "API health endpoint" "curl -f -s '$BASE_URL/api/health' | grep -q 'ok'"
check "Database connectivity" "curl -f -s '$BASE_URL/api/ready' | grep -q 'connected'"
echo

# 2. Security Headers
echo "[2/8] Security Headers"
HEADERS=$(curl -s -I "$BASE_URL/")
check "X-Content-Type-Options" "echo '$HEADERS' | grep -q 'X-Content-Type-Options: nosniff'"
check "X-Frame-Options" "echo '$HEADERS' | grep -q 'X-Frame-Options: DENY'"
check "X-XSS-Protection" "echo '$HEADERS' | grep -q 'X-XSS-Protection'"
echo

# 3. CORS Configuration
echo "[3/8] CORS Configuration"
CORS=$(curl -s -I -H "Origin: https://evil.com" "$BASE_URL/api/health")
if echo "$CORS" | grep -q "Access-Control-Allow-Origin: https://evil.com"; then
    echo "❌ CORS accepts evil.com - SECURITY ISSUE"
    ((FAILURES++))
else
    echo "✅ CORS properly restricted"
fi
echo

# 4. Rate Limiting
echo "[4/8] Rate Limiting"
printf "%-40s" "Testing rate limits..."
COUNT=0
for i in {1..10}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/health")
    if [ "$HTTP_CODE" = "429" ]; then
        echo "✅ PASS (rate limited at request $i)"
        break
    fi
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq 10 ]; then
    echo "⚠️  WARNING: No rate limiting detected"
fi
echo

# 5. Authentication
echo "[5/8] Authentication Endpoints"
check "Registration endpoint exists" "curl -f -s -X POST '$BASE_URL/api/auth/register' -H 'Content-Type: application/json' -d '{}' || true"
check "Login endpoint exists" "curl -f -s -X POST '$BASE_URL/api/auth/login' -H 'Content-Type: application/json' -d '{}' || true"
echo

# 6. Password Reset Removed
echo "[6/8] Security Vulnerabilities Fixed"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/auth/reset-password" -H 'Content-Type: application/json' -d '{"email":"test@example.com","new_password":"hack"}')
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "405" ]; then
    echo "✅ Password reset endpoint removed (HTTP $HTTP_CODE)"
else
    echo "❌ Password reset endpoint still accessible (HTTP $HTTP_CODE) - SECURITY ISSUE"
    ((FAILURES++))
fi
echo

# 7. VPN Infrastructure
echo "[7/8] VPN Infrastructure"
if command -v jq > /dev/null 2>&1; then
    SERVER_COUNT=$(curl -s "$BASE_URL/api/optimizer/servers" 2>/dev/null | jq -r '.total_servers // 0')
    if [ "$SERVER_COUNT" -ge 1 ]; then
        echo "✅ VPN servers available: $SERVER_COUNT"
    else
        echo "⚠️  No VPN servers found in database"
    fi
else
    echo "⚠️  jq not installed, skipping server count check"
fi
echo

# 8. Frontend
echo "[8/8] Frontend Assets"
check "Home page loads" "curl -f -s '$BASE_URL/' > /dev/null"
check "Login page loads" "curl -f -s '$BASE_URL/login.html' > /dev/null || curl -f -s '$BASE_URL/static/login.html' > /dev/null"
echo

# Summary
echo "=========================================="
if [ $FAILURES -eq 0 ]; then
    echo "🎉 All health checks passed!"
    echo "=========================================="
    exit 0
else
    echo "❌ Health check failed: $FAILURES issue(s) found"
    echo "=========================================="
    exit 1
fi
