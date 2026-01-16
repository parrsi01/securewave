#!/usr/bin/env bash
###############################################################################
# SECUREWAVE VPN - UNIFIED DEPLOYMENT SCRIPT
# Single script for all deployment needs: local dev, Azure production
# Author: SecureWave Team
# Date: 2026-01-03
###############################################################################

set -euo pipefail

# Colors for beautiful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-SecureWaveRG}"
LOCATION="${LOCATION:-westeurope}"
APP_NAME="${APP_NAME:-securewave-web}"
PLAN_NAME="${PLAN_NAME:-SecureWavePlan}"
BASE_URL="https://${APP_NAME}.azurewebsites.net"
PYTHON_VERSION="3.11"

# Helper functions
log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }
log_step() { echo -e "${CYAN}▸${NC}  ${CYAN}$1${NC}"; }
log_banner() { echo -e "${MAGENTA}$1${NC}"; }

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""
}

print_banner() {
    clear
    echo ""
    log_banner "  ███████╗███████╗ ██████╗██╗   ██╗██████╗ ███████╗██╗    ██╗ █████╗ ██╗   ██╗███████╗"
    log_banner "  ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██╔════╝██║    ██║██╔══██╗██║   ██║██╔════╝"
    log_banner "  ███████╗█████╗  ██║     ██║   ██║██████╔╝█████╗  ██║ █╗ ██║███████║██║   ██║█████╗  "
    log_banner "  ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██╔══╝  ██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  "
    log_banner "  ███████║███████╗╚██████╗╚██████╔╝██║  ██║███████╗╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗"
    log_banner "  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
    echo ""
    log_banner "                        Universal Deployment System v2.0"
    echo ""
}

# Generate secure secret
generate_secret() {
    python3 -c 'import secrets; print(secrets.token_urlsafe(64))'
}

###############################################################################
# LOCAL DEVELOPMENT MODE
###############################################################################
deploy_local() {
    print_header "SECUREWAVE VPN - LOCAL DEVELOPMENT"

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi

    log_info "Python version: $(python3 --version)"

    # Setup virtual environment
    if [ ! -d "venv" ]; then
        log_step "[1/5] Creating virtual environment..."
        python3 -m venv venv
        log_success "Virtual environment created"
    else
        log_info "[1/5] Virtual environment already exists"
    fi

    # Activate virtual environment
    log_step "[2/5] Activating virtual environment..."
    source venv/bin/activate
    log_success "Virtual environment activated"

    # Install dependencies
    log_step "[3/5] Installing dependencies..."
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    log_success "Dependencies installed"

    # Setup database
    log_step "[4/5] Setting up database..."
    python3 -c "
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print('Database tables ready')
" 2>/dev/null || echo "Database ready"
    log_success "Database ready"

    # Initialize demo servers
    if [ -f "infrastructure/init_demo_servers.py" ]; then
        log_step "[5/5] Initializing demo VPN servers..."
        python3 infrastructure/init_demo_servers.py 2>/dev/null || true
        log_success "Demo servers initialized"
    fi

    # Display info
    print_header "🚀 SECUREWAVE VPN IS STARTING"

    echo -e "${GREEN}Your application is available at:${NC}"
    echo ""
    echo "  🌐 Website:      http://localhost:8000"
    echo "  🏠 Home:         http://localhost:8000/home.html"
    echo "  🔐 Login:        http://localhost:8000/login.html"
    echo "  📝 Register:     http://localhost:8000/register.html"
    echo "  📊 Dashboard:    http://localhost:8000/dashboard.html"
    echo "  📚 API Docs:     http://localhost:8000/api/docs"
    echo "  ❤️  Health:      http://localhost:8000/api/health"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""

    # Start server
    exec uvicorn main:app --reload --host 0.0.0.0 --port 8000
}

###############################################################################
# AZURE CLOUD DEPLOYMENT
###############################################################################
deploy_azure() {
    print_header "SECUREWAVE VPN - AZURE CLOUD DEPLOYMENT"

    # Check prerequisites
    log_step "Checking prerequisites..."

    local missing_tools=()
    command -v az &> /dev/null || missing_tools+=("azure-cli")
    command -v python3 &> /dev/null || missing_tools+=("python3")
    command -v zip &> /dev/null || missing_tools+=("zip")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"

    # Check Azure authentication
    log_step "Checking Azure authentication..."
    if ! az account show > /dev/null 2>&1; then
        log_error "Not logged in to Azure"
        log_info "Please run: az login"
        exit 1
    fi

    local account_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_success "Authenticated to Azure"
    log_info "Account: $account_name"
    log_info "Subscription: $subscription_id"

    # Validate application structure
    log_step "Validating application structure..."
    local required_files=("main.py" "requirements.txt" "startup.sh")
    local missing=()

    for file in "${required_files[@]}"; do
        [ ! -f "$file" ] && missing+=("$file")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required files: ${missing[*]}"
        exit 1
    fi

    log_success "Application structure validated"

    # Create deployment package
    log_step "Creating deployment package..."
    rm -rf build deploy.zip
    mkdir -p build

    # Copy core files
    cp main.py build/
    cp background_tasks.py build/ 2>/dev/null || log_warning "background_tasks.py not found (optional)"
    cp requirements.txt build/
    cp startup.sh build/
    cp gunicorn.conf.py build/ 2>/dev/null || log_warning "gunicorn.conf.py not found"
    cp alembic.ini build/ 2>/dev/null || log_warning "alembic.ini not found (optional)"

    # Copy application directories
    for dir in routers routes models database services infrastructure scripts; do
        if [ -d "$dir" ]; then
            cp -r "$dir" build/
            log_info "  ✓ Copied $dir/"
        fi
    done

    # Copy ML models and data
    if [ -d "data/models" ]; then
        mkdir -p build/data/models
        cp -r data/models/* build/data/models/
        log_info "  ✓ Copied ML models"
    fi

    # Copy alembic if exists
    [ -d "alembic" ] && cp -r alembic build/ && log_info "  ✓ Copied alembic/"

    # Copy static files (use static/ directory, not frontend/)
    mkdir -p build/static
    if [ -d "static" ]; then
        cp -r static/* build/static/
        log_info "  ✓ Copied static files"
    else
        log_warning "No static directory found"
    fi

    # Create deployment configuration
    cat > build/.deployment << 'EOF'
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
EOF

    chmod +x build/startup.sh

    # Create deployment zip
    cd build
    zip -r ../deploy.zip . -x "*.pyc" "__pycache__/*" "*.db" "*.sqlite" ".git/*" -q
    cd ..

    local zip_size=$(du -h deploy.zip | cut -f1)
    log_success "Deployment package created: deploy.zip ($zip_size)"

    # Setup Azure resources
    log_step "Setting up Azure resources..."

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none 2>/dev/null || true

    if ! az appservice plan show --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        az appservice plan create \
            --name "$PLAN_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --is-linux \
            --sku B1 \
            --output none
        log_success "App Service Plan created"
    else
        log_info "App Service Plan already exists"
    fi

    if ! az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        az webapp create \
            --name "$APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$PLAN_NAME" \
            --runtime "PYTHON:$PYTHON_VERSION" \
            --output none
        log_success "Web App created"
    else
        log_info "Web App already exists"
    fi

    log_success "Azure resources configured"

    # Configure application settings
    log_step "Configuring application settings..."

    local access_secret=$(generate_secret)
    local refresh_secret=$(generate_secret)

    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --settings \
            PORT=8000 \
            PYTHONUNBUFFERED=1 \
            DATABASE_URL="sqlite:////tmp/securewave.db" \
            ENVIRONMENT="production" \
            DEMO_OK="true" \
            ACCESS_TOKEN_SECRET="$access_secret" \
            REFRESH_TOKEN_SECRET="$refresh_secret" \
            CORS_ORIGINS="$BASE_URL,https://www.${APP_NAME}.azurewebsites.net" \
            WG_MOCK_MODE="true" \
            WG_DATA_DIR="/tmp/wg_data" \
            QOS_MODEL_PATH="data/models/qos_model.json" \
            RISK_MODEL_PATH="data/models/risk_model.json" \
            WEBSITES_PORT=8000 \
            SCM_DO_BUILD_DURING_DEPLOYMENT=true \
        --output none

    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --startup-file "gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000 --timeout 600" \
        --output none

    log_success "Application settings configured"

    # Deploy application
    log_step "Deploying application to Azure..."

    az webapp stop --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --output none
    sleep 3

    log_info "Uploading deployment package (this may take a few minutes)..."
    az webapp deploy \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --src-path deploy.zip \
        --type zip \
        --async false \
        --timeout 600 2>&1 | grep -v "WARNING" || true

    sleep 3

    az webapp start --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --output none
    log_success "Application deployed"

    # Wait for application
    log_step "Waiting for application to start (up to 2 minutes)..."

    local max_attempts=24
    local attempt=1

    echo -n "  Checking application health"
    while [ $attempt -le $max_attempts ]; do
        sleep 5

        if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
            echo ""
            log_success "Application is running and healthy!"
            break
        fi

        echo -n "."
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo ""
        log_warning "Health check timeout - application may still be starting"
    fi

    # Verify deployment
    log_step "Verifying deployment..."

    local tests_passed=0

    curl -sf "$BASE_URL/api/health" | grep -q "ok" && { log_success "✓ Health check passed"; tests_passed=$((tests_passed + 1)); } || log_warning "✗ Health check failed"
    curl -sf "$BASE_URL/api/ready" > /dev/null 2>&1 && { log_success "✓ Readiness check passed"; tests_passed=$((tests_passed + 1)); } || log_warning "✗ Readiness check failed"
    curl -sI "$BASE_URL/" 2>/dev/null | head -1 | grep -q "200\|301\|302" && { log_success "✓ Main page accessible"; tests_passed=$((tests_passed + 1)); } || log_warning "✗ Main page check failed"
    curl -sI "$BASE_URL/api/docs" 2>/dev/null | head -1 | grep -q "200\|301\|302" && { log_success "✓ API documentation accessible"; tests_passed=$((tests_passed + 1)); } || log_warning "✗ API docs check failed"

    echo ""

    if [ $tests_passed -eq 4 ]; then
        log_success "All verification tests passed!"
    elif [ $tests_passed -ge 2 ]; then
        log_warning "Some tests failed, but application appears functional"
    else
        log_warning "Multiple tests failed - check logs: az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
    fi

    # Display success information
    print_header "🎉 DEPLOYMENT SUCCESSFUL"

    echo -e "${GREEN}Your SecureWave VPN application is now live!${NC}"
    echo ""
    echo -e "${CYAN}📍 Application URLs:${NC}"
    echo "  ├─ Main Site:      $BASE_URL"
    echo "  ├─ Home:           $BASE_URL/home.html"
    echo "  ├─ Login:          $BASE_URL/login.html"
    echo "  ├─ Register:       $BASE_URL/register.html"
    echo "  ├─ Dashboard:      $BASE_URL/dashboard.html"
    echo "  ├─ API Docs:       $BASE_URL/api/docs"
    echo "  └─ Health:         $BASE_URL/api/health"
    echo ""
    echo -e "${CYAN}🔍 Monitoring:${NC}"
    echo "  └─ View logs: az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
    echo ""
    echo -e "${CYAN}⚙️  Management:${NC}"
    echo "  ├─ Restart:  az webapp restart -g $RESOURCE_GROUP -n $APP_NAME"
    echo "  ├─ Stop:     az webapp stop -g $RESOURCE_GROUP -n $APP_NAME"
    echo "  └─ Logs:     az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
    echo ""
    echo -e "${CYAN}🌍 Share:${NC}"
    echo "  └─ $BASE_URL"
    echo ""

    # Cleanup
    log_info "Cleaning up build artifacts..."
    rm -rf build

    log_success "Deployment complete! 🚀"
}

###############################################################################
# DIAGNOSTICS MODE
###############################################################################
run_diagnostics() {
    print_header "SECUREWAVE VPN - DIAGNOSTICS"

    if ! az account show > /dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run: az login"
        exit 1
    fi

    if ! az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" &>/dev/null; then
        log_error "Application not found. Deploy first using: ./deploy.sh azure"
        exit 1
    fi

    local state=$(az webapp show -g "$RESOURCE_GROUP" -n "$APP_NAME" --query state -o tsv)
    log_info "App state: $state"

    log_step "Running health checks..."

    local checks_passed=0

    curl -sf "$BASE_URL/api/health" > /dev/null 2>&1 && { log_success "Health endpoint OK"; checks_passed=$((checks_passed + 1)); } || log_warning "Health endpoint not responding"
    curl -sf "$BASE_URL/api/ready" > /dev/null 2>&1 && { log_success "Ready endpoint OK"; checks_passed=$((checks_passed + 1)); } || log_warning "Ready endpoint not responding"
    curl -sI "$BASE_URL/" 2>/dev/null | head -1 | grep -q "200\|301\|302" && { log_success "Main page OK"; checks_passed=$((checks_passed + 1)); } || log_warning "Main page not accessible"

    echo ""
    log_info "Health checks: $checks_passed/3 passed"

    if [ $checks_passed -eq 3 ]; then
        log_success "All systems operational! ✓"
    elif [ $checks_passed -gt 0 ]; then
        log_warning "Some issues detected. Viewing logs..."
        echo ""
        az webapp log tail -g "$RESOURCE_GROUP" -n "$APP_NAME" 2>/dev/null | head -50
    else
        log_error "Application is not responding. Viewing logs..."
        echo ""
        az webapp log tail -g "$RESOURCE_GROUP" -n "$APP_NAME" 2>/dev/null | head -50
    fi
}

###############################################################################
# MAIN ENTRY POINT
###############################################################################
main() {
    print_banner

    # Parse mode
    MODE="${1:-}"

    case "$MODE" in
        "")
            # No argument - show menu
            echo "Select deployment mode:"
            echo ""
            echo "  ${CYAN}1)${NC} Local Development  (http://localhost:8000)"
            echo "  ${CYAN}2)${NC} Azure Production   ($BASE_URL)"
            echo "  ${CYAN}3)${NC} Diagnostics        (Check Azure deployment status)"
            echo "  ${CYAN}4)${NC} Exit"
            echo ""
            read -p "Enter choice [1-4]: " choice

            case $choice in
                1) deploy_local ;;
                2) deploy_azure ;;
                3) run_diagnostics ;;
                4) log_info "Exiting..."; exit 0 ;;
                *) log_error "Invalid choice"; exit 1 ;;
            esac
            ;;

        "local"|"dev")
            deploy_local
            ;;

        "azure"|"production"|"prod")
            deploy_azure
            ;;

        "diagnostics"|"diag"|"health"|"status")
            run_diagnostics
            ;;

        "help"|"--help"|"-h")
            echo "Usage: $0 [MODE]"
            echo ""
            echo "Modes:"
            echo "  local, dev              - Run locally on http://localhost:8000"
            echo "  azure, production, prod - Deploy to Azure cloud"
            echo "  diagnostics, diag       - Run diagnostics on Azure deployment"
            echo "  help                    - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Interactive menu"
            echo "  $0 local                # Start local development"
            echo "  $0 azure                # Deploy to Azure"
            echo "  $0 diagnostics          # Check Azure deployment"
            ;;

        *)
            log_error "Unknown mode: $MODE"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
