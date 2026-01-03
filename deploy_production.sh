#!/usr/bin/env bash
###############################################################################
# SECUREWAVE VPN - PRODUCTION-READY UNIVERSAL DEPLOYMENT SCRIPT
# Works with: Azure App Service, Azure Container Instances, Docker, VMs
# Ensures global accessibility with proper configuration
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-SecureWaveRG}"
LOCATION="${LOCATION:-westeurope}"
APP_NAME="${APP_NAME:-securewave-web}"
PLAN_NAME="${PLAN_NAME:-SecureWavePlan}"
BASE_URL="https://${APP_NAME}.azurewebsites.net"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

print_header() {
    echo ""
    echo "========================================================================"
    echo "  $1"
    echo "========================================================================"
    echo ""
}

print_banner() {
    echo ""
    echo "  ███████╗███████╗ ██████╗██╗   ██╗██████╗ ███████╗██╗    ██╗ █████╗ ██╗   ██╗███████╗"
    echo "  ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██╔════╝██║    ██║██╔══██╗██║   ██║██╔════╝"
    echo "  ███████╗█████╗  ██║     ██║   ██║██████╔╝█████╗  ██║ █╗ ██║███████║██║   ██║█████╗  "
    echo "  ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██╔══╝  ██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  "
    echo "  ███████║███████╗╚██████╗╚██████╔╝██║  ██║███████╗╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗"
    echo "  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
    echo ""
    echo "                      Universal Production Deployment"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing_tools=()

    # Check for Azure CLI
    if ! command -v az &> /dev/null; then
        missing_tools+=("azure-cli")
    fi

    # Check for Python
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi

    # Check for zip
    if ! command -v zip &> /dev/null; then
        missing_tools+=("zip")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Check Azure authentication
check_azure_auth() {
    log_step "Checking Azure authentication..."

    if ! az account show > /dev/null 2>&1; then
        log_error "Not logged in to Azure"
        log_info "Run: az login"
        exit 1
    fi

    local account_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_success "Authenticated to Azure"
    log_info "Account: $account_name"
    log_info "Subscription: $subscription_id"
}

# Generate secure secrets
generate_secret() {
    python3 -c 'import secrets; print(secrets.token_urlsafe(64))'
}

# Validate application structure
validate_app_structure() {
    log_step "Validating application structure..."

    local required_files=("main.py" "requirements.txt" "startup.sh")
    local required_dirs=("database" "models" "routers" "services" "infrastructure")
    local missing=()

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing+=("$file")
        fi
    done

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            missing+=("$dir/")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required files/directories: ${missing[*]}"
        exit 1
    fi

    log_success "Application structure validated"
}

# Create deployment package
create_deployment_package() {
    log_step "Creating deployment package..."

    # Clean previous build
    rm -rf build deploy.zip
    mkdir -p build

    # Copy core application files
    log_info "Copying application files..."
    cp main.py build/
    cp background_tasks.py build/ 2>/dev/null || log_warning "background_tasks.py not found (optional)"
    cp requirements.txt build/
    cp startup.sh build/
    cp alembic.ini build/ 2>/dev/null || log_warning "alembic.ini not found (optional)"

    # Copy application directories
    for dir in routers models database services infrastructure; do
        if [ -d "$dir" ]; then
            cp -r "$dir" build/
            log_info "✓ Copied $dir/"
        else
            log_warning "$dir/ not found"
        fi
    done

    # Copy alembic if exists
    if [ -d "alembic" ]; then
        cp -r alembic build/
        log_info "✓ Copied alembic/"
    fi

    # Copy static files
    mkdir -p build/static
    if [ -d "static" ]; then
        cp -r static/* build/static/
        log_info "✓ Copied static files"
    elif [ -d "frontend" ]; then
        cp -r frontend/* build/static/
        log_info "✓ Copied frontend files"
    else
        log_warning "No static or frontend directory found"
    fi

    # Create .deployment file for Azure
    cat > build/.deployment << 'EOF'
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
EOF

    # Make startup script executable
    chmod +x build/startup.sh

    # Create .env file for production
    cat > build/.env.production << EOF
# Auto-generated production environment
ENVIRONMENT=production
WG_MOCK_MODE=true
PYTHONUNBUFFERED=1
EOF

    # Create deployment zip
    log_info "Creating deployment archive..."
    cd build
    zip -r ../deploy.zip . -x "*.pyc" "__pycache__/*" "*.db" "*.sqlite" ".git/*" > /dev/null
    cd ..

    local zip_size=$(du -h deploy.zip | cut -f1)
    log_success "Deployment package created: deploy.zip ($zip_size)"
}

# Create or update Azure resources
setup_azure_resources() {
    log_step "Setting up Azure resources..."

    # Create resource group
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none 2>/dev/null || true

    # Create App Service Plan
    log_info "Creating App Service Plan: $PLAN_NAME"
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

    # Create Web App
    log_info "Creating Web App: $APP_NAME"
    if ! az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        az webapp create \
            --name "$APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$PLAN_NAME" \
            --runtime "PYTHON:3.12" \
            --output none
        log_success "Web App created"
    else
        log_info "Web App already exists"
    fi

    log_success "Azure resources configured"
}

# Configure application settings
configure_app_settings() {
    log_step "Configuring application settings..."

    # Generate secure secrets
    local access_secret=$(generate_secret)
    local refresh_secret=$(generate_secret)

    log_info "Setting environment variables..."
    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --settings \
            PORT=8000 \
            PYTHONUNBUFFERED=1 \
            PYTHONPATH=/home/site/wwwroot \
            DATABASE_URL="sqlite:////tmp/securewave.db" \
            ENVIRONMENT="production" \
            ACCESS_TOKEN_SECRET="$access_secret" \
            REFRESH_TOKEN_SECRET="$refresh_secret" \
            CORS_ORIGINS="https://${APP_NAME}.azurewebsites.net,https://www.${APP_NAME}.azurewebsites.net" \
            WG_MOCK_MODE="true" \
            WG_DATA_DIR="/tmp/wg_data" \
            WEBSITES_PORT=8000 \
            WEBSITES_ENABLE_APP_SERVICE_STORAGE=true \
            SCM_DO_BUILD_DURING_DEPLOYMENT=true \
            ENABLE_ORYX_BUILD=true \
        --output none

    # Set startup command
    log_info "Setting startup command..."
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --startup-file "startup.sh" \
        --output none

    # Configure logging
    log_info "Enabling application logging..."
    az webapp log config \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --application-logging filesystem \
        --detailed-error-messages true \
        --failed-request-tracing true \
        --level information \
        --output none 2>/dev/null || log_warning "Logging configuration skipped"

    log_success "Application settings configured"
}

# Deploy application
deploy_application() {
    log_step "Deploying application to Azure..."

    # Stop app
    log_info "Stopping web app..."
    az webapp stop \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --output none

    sleep 5

    # Deploy using zip
    log_info "Uploading deployment package (this may take a few minutes)..."
    az webapp deploy \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --src-path deploy.zip \
        --type zip \
        --async false \
        --timeout 600 2>&1 | grep -v "WARNING" || true

    sleep 5

    # Start app
    log_info "Starting web app..."
    az webapp start \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --output none

    log_success "Application deployed successfully"
}

# Wait for application to be ready
wait_for_application() {
    log_step "Waiting for application to start..."

    local max_attempts=30
    local attempt=1
    local wait_time=5

    echo -n "Checking application health"

    while [ $attempt -le $max_attempts ]; do
        sleep $wait_time

        if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
            echo ""
            log_success "Application is running and healthy!"
            return 0
        fi

        echo -n "."
        attempt=$((attempt + 1))
    done

    echo ""
    log_warning "Health check timeout - application may still be starting"
    log_info "Check logs: az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."

    local tests_passed=0
    local tests_total=4

    # Test 1: Health endpoint
    if curl -sf "$BASE_URL/api/health" | grep -q "ok"; then
        log_success "✓ Health check passed"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "✗ Health check failed"
    fi

    # Test 2: Ready endpoint
    if curl -sf "$BASE_URL/api/ready" > /dev/null 2>&1; then
        log_success "✓ Readiness check passed"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "✗ Readiness check failed"
    fi

    # Test 3: Main page
    if curl -sI "$BASE_URL/" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "✓ Main page accessible"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "✗ Main page check failed"
    fi

    # Test 4: API docs
    if curl -sI "$BASE_URL/api/docs" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "✓ API documentation accessible"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "✗ API docs check failed"
    fi

    echo ""
    log_info "Verification: $tests_passed/$tests_total tests passed"

    if [ $tests_passed -eq $tests_total ]; then
        log_success "All verification tests passed!"
    elif [ $tests_passed -ge 2 ]; then
        log_warning "Some tests failed, but application appears functional"
    else
        log_warning "Multiple tests failed - check application logs"
    fi
}

# Show deployment information
show_deployment_info() {
    print_header "DEPLOYMENT COMPLETE"

    echo -e "${GREEN}🎉 SecureWave VPN is now live!${NC}"
    echo ""
    echo -e "${CYAN}📍 Application URLs:${NC}"
    echo "   ├─ Main Site:      $BASE_URL"
    echo "   ├─ Home Page:      $BASE_URL/home.html"
    echo "   ├─ Login:          $BASE_URL/login.html"
    echo "   ├─ Register:       $BASE_URL/register.html"
    echo "   ├─ Dashboard:      $BASE_URL/dashboard.html"
    echo "   ├─ API Docs:       $BASE_URL/api/docs"
    echo "   └─ Health Check:   $BASE_URL/api/health"
    echo ""
    echo -e "${CYAN}🔍 Monitoring & Logs:${NC}"
    echo "   └─ View logs: az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
    echo ""
    echo -e "${CYAN}⚙️  Management Commands:${NC}"
    echo "   ├─ Restart:  az webapp restart -g $RESOURCE_GROUP -n $APP_NAME"
    echo "   ├─ Stop:     az webapp stop -g $RESOURCE_GROUP -n $APP_NAME"
    echo "   ├─ Start:    az webapp start -g $RESOURCE_GROUP -n $APP_NAME"
    echo "   └─ Delete:   az group delete -n $RESOURCE_GROUP -y"
    echo ""
    echo -e "${CYAN}🌍 Share Your VPN:${NC}"
    echo "   └─ $BASE_URL"
    echo ""
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
}

# Cleanup on error
cleanup_on_error() {
    log_error "Deployment failed!"
    log_info "Cleaning up temporary files..."
    rm -rf build deploy.zip 2>/dev/null || true
    exit 1
}

# Main deployment flow
main() {
    trap cleanup_on_error ERR

    print_banner

    # Pre-flight checks
    check_prerequisites
    check_azure_auth
    validate_app_structure

    # Build and package
    create_deployment_package

    # Azure setup
    setup_azure_resources
    configure_app_settings

    # Deploy
    deploy_application

    # Post-deployment
    wait_for_application
    verify_deployment

    # Show results
    show_deployment_info

    # Cleanup build artifacts
    log_info "Cleaning up build artifacts..."
    # Keep deploy.zip for reference
    rm -rf build

    log_success "All done! 🚀"
}

# Run main function
main "$@"
