#!/usr/bin/env bash
###############################################################################
# SECUREWAVE VPN - DIAGNOSTIC AND FIX SCRIPT
# Diagnoses and fixes common deployment issues
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RESOURCE_GROUP="${RESOURCE_GROUP:-SecureWaveRG}"
APP_NAME="${APP_NAME:-securewave-web}"
BASE_URL="https://${APP_NAME}.azurewebsites.net"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

print_header() {
    echo ""
    echo "========================================================================"
    echo "  $1"
    echo "========================================================================"
    echo ""
}

# Check application status
check_status() {
    print_header "APPLICATION STATUS CHECK"

    # Check if app exists
    if ! az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" &>/dev/null; then
        log_error "Application not found"
        log_info "Run deployment script first: ./deploy_production.sh"
        exit 1
    fi

    # Get app state
    local state=$(az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" --query state -o tsv)
    log_info "App state: $state"

    # Check health endpoint
    log_info "Checking health endpoint..."
    if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
        log_success "Health endpoint responding"
    else
        log_warning "Health endpoint not responding"
    fi

    # Check main page
    log_info "Checking main page..."
    local response=$(curl -sI "$BASE_URL/" 2>/dev/null | head -1 || echo "")
    if echo "$response" | grep -q "200\|301\|302"; then
        log_success "Main page accessible"
    else
        log_warning "Main page not accessible"
    fi
}

# View recent logs
view_logs() {
    print_header "RECENT APPLICATION LOGS"

    log_info "Fetching last 50 lines of logs..."
    echo ""

    az webapp log tail \
        -g "$RESOURCE_GROUP" \
        -n "$APP_NAME" \
        --filter ".*" 2>/dev/null | head -50 || {
            log_warning "Could not fetch logs via tail, trying download..."

            # Try downloading logs
            local log_file="logs_$(date +%Y%m%d_%H%M%S).zip"
            az webapp log download \
                -g "$RESOURCE_GROUP" \
                -n "$APP_NAME" \
                --log-file "$log_file" 2>/dev/null || {
                    log_error "Could not fetch logs"
                }
        }
}

# Check environment variables
check_env_vars() {
    print_header "ENVIRONMENT VARIABLES CHECK"

    log_info "Checking critical environment variables..."

    local settings=$(az webapp config appsettings list \
        -g "$RESOURCE_GROUP" \
        -n "$APP_NAME" -o json)

    local required_vars=("PORT" "DATABASE_URL" "PYTHONPATH" "WG_MOCK_MODE")

    for var in "${required_vars[@]}"; do
        if echo "$settings" | grep -q "\"name\": \"$var\""; then
            local value=$(echo "$settings" | grep -A1 "\"name\": \"$var\"" | grep "value" | cut -d'"' -f4)
            log_success "$var is set: $value"
        else
            log_warning "$var is not set"
        fi
    done
}

# Fix common issues
fix_issues() {
    print_header "APPLYING FIXES"

    log_info "Restarting application..."
    az webapp restart -g "$RESOURCE_GROUP" -n "$APP_NAME" --output none

    log_info "Waiting for application to start..."
    sleep 10

    local max_attempts=20
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
            log_success "Application is now responding!"
            return 0
        fi
        sleep 3
        echo -n "."
        attempt=$((attempt + 1))
    done

    echo ""
    log_warning "Application still not responding after restart"
    log_info "Checking logs for errors..."
    view_logs
}

# Run health checks
run_health_checks() {
    print_header "COMPREHENSIVE HEALTH CHECKS"

    local checks_passed=0
    local checks_total=6

    # Check 1: Azure resource exists
    if az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" &>/dev/null; then
        log_success "Azure resource exists"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Azure resource not found"
    fi

    # Check 2: App is running
    local state=$(az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" --query state -o tsv 2>/dev/null || echo "Unknown")
    if [ "$state" == "Running" ]; then
        log_success "Application state: Running"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "Application state: $state"
    fi

    # Check 3: Health endpoint
    if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
        log_success "Health endpoint responding"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "Health endpoint not responding"
    fi

    # Check 4: Ready endpoint
    if curl -sf "$BASE_URL/api/ready" > /dev/null 2>&1; then
        log_success "Ready endpoint responding"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "Ready endpoint not responding"
    fi

    # Check 5: Main page
    if curl -sI "$BASE_URL/" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "Main page accessible"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "Main page not accessible"
    fi

    # Check 6: API docs
    if curl -sI "$BASE_URL/api/docs" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "API documentation accessible"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "API documentation not accessible"
    fi

    echo ""
    log_info "Health checks: $checks_passed/$checks_total passed"

    if [ $checks_passed -eq $checks_total ]; then
        log_success "All health checks passed! 🎉"
        return 0
    elif [ $checks_passed -ge 3 ]; then
        log_warning "Some checks failed, but application appears functional"
        return 1
    else
        log_error "Multiple health checks failed"
        return 2
    fi
}

# Main menu
show_menu() {
    print_header "SECUREWAVE VPN - DIAGNOSTICS & FIXES"

    echo "What would you like to do?"
    echo ""
    echo "  1) Run health checks"
    echo "  2) View application logs"
    echo "  3) Check environment variables"
    echo "  4) Restart application"
    echo "  5) Run full diagnostic and fix"
    echo "  6) Exit"
    echo ""
    read -p "Enter choice [1-6]: " choice

    case $choice in
        1)
            run_health_checks
            ;;
        2)
            view_logs
            ;;
        3)
            check_env_vars
            ;;
        4)
            fix_issues
            ;;
        5)
            check_status
            check_env_vars
            run_health_checks || fix_issues
            ;;
        6)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Run with command line args or show menu
if [ $# -eq 0 ]; then
    show_menu
else
    case "$1" in
        status)
            check_status
            ;;
        logs)
            view_logs
            ;;
        env)
            check_env_vars
            ;;
        fix)
            fix_issues
            ;;
        health)
            run_health_checks
            ;;
        full)
            check_status
            check_env_vars
            run_health_checks || fix_issues
            ;;
        *)
            echo "Usage: $0 [status|logs|env|fix|health|full]"
            exit 1
            ;;
    esac
fi
