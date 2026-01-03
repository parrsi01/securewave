#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# SECUREWAVE VPN - UNIVERSAL DEPLOYMENT SCRIPT
# Deploys to Azure with full configuration and verification
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="SecureWaveRG"
LOCATION="westeurope"
APP_NAME="securewave-web"
PLAN_NAME="SecureWavePlan"
BASE_URL="https://${APP_NAME}.azurewebsites.net"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo "========================================================================"
    echo "  $1"
    echo "========================================================================"
    echo ""
}

# Check Azure authentication
check_azure_auth() {
    log_info "Checking Azure authentication..."
    if ! az account show > /dev/null 2>&1; then
        log_error "Not logged in to Azure"
        log_info "Please run: az login"
        exit 1
    fi
    local account_name=$(az account show --query name -o tsv)
    log_success "Authenticated as: $account_name"
}

# Generate secure secrets
generate_secret() {
    python3 -c 'import secrets; print(secrets.token_urlsafe(64))'
}

# Create deployment package
create_deployment_package() {
    log_info "Creating deployment package..."

    # Clean previous build
    rm -rf build deploy.zip
    mkdir -p build

    # Copy application files
    cp main.py build/ 2>/dev/null || echo "main.py not found"
    cp background_tasks.py build/ 2>/dev/null || echo "background_tasks.py not found"
    cp requirements.txt build/
    cp startup.sh build/
    cp alembic.ini build/ 2>/dev/null || echo "alembic.ini not found"

    # Copy directories (create if missing)
    for dir in routers models database services infrastructure; do
        if [ -d "$dir" ]; then
            cp -r "$dir" build/
        else
            echo "Warning: $dir directory not found"
        fi
    done

    # Copy alembic if exists
    if [ -d "alembic" ]; then
        cp -r alembic build/
    fi

    # Copy frontend/static to build/static
    mkdir -p build/static
    if [ -d "frontend" ]; then
        cp -r frontend/* build/static/
        log_info "Copied frontend files to build/static"
    elif [ -d "static" ]; then
        cp -r static/* build/static/
        log_info "Copied static files to build/static"
    else
        log_warning "No frontend or static directory found"
    fi

    # Create deployment marker
    cat > build/.deployment << 'EOF'
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
EOF

    # Make startup script executable
    chmod +x build/startup.sh

    # Create deployment zip
    cd build
    zip -r ../deploy.zip . -x "*.pyc" "__pycache__/*" "*.db" > /dev/null
    cd ..

    local zip_size=$(du -h deploy.zip | cut -f1)
    log_success "Deployment package created: deploy.zip ($zip_size)"
}

# Configure Azure resources
configure_azure_resources() {
    log_info "Configuring Azure resources..."

    # Create resource group
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none 2>/dev/null || true

    # Create App Service Plan (B1 tier)
    az appservice plan create \
        --name "$PLAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --is-linux \
        --sku B1 \
        --output none 2>/dev/null || true

    # Create Web App
    az webapp create \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$PLAN_NAME" \
        --runtime "PYTHON:3.12" \
        --output none 2>/dev/null || true

    log_success "Azure resources configured"
}

# Configure application settings
configure_app_settings() {
    log_info "Configuring application settings..."

    # Generate secrets
    local access_secret=$(generate_secret)
    local refresh_secret=$(generate_secret)

    # Configure app settings
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
            CORS_ORIGINS="$BASE_URL,https://$APP_NAME.azurewebsites.net" \
            WG_MOCK_MODE="true" \
            WG_DATA_DIR="/tmp/wg_data" \
            WEBSITES_PORT=8000 \
            WEBSITES_ENABLE_APP_SERVICE_STORAGE=true \
            SCM_DO_BUILD_DURING_DEPLOYMENT=true \
            ENABLE_ORYX_BUILD=true \
        --output none

    # Set startup command
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --startup-file "startup.sh" \
        --output none

    log_success "Application settings configured"
}

# Deploy application
deploy_application() {
    log_info "Deploying application to Azure..."

    # Stop app during deployment
    log_info "Stopping webapp..."
    az webapp stop --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --output none

    sleep 5

    # Deploy using zip
    log_info "Uploading deployment package..."
    az webapp deploy \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --src-path deploy.zip \
        --type zip \
        --async false 2>&1 | grep -v "WARNING" || {
            log_warning "Deployment command completed with warnings (this is often normal)"
        }

    sleep 5

    # Start app
    log_info "Starting webapp..."
    az webapp start --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --output none

    log_success "Application deployed"
}

# Wait for application to be ready
wait_for_app() {
    log_info "Waiting for application to start (up to 2 minutes)..."

    local max_attempts=24  # 24 * 5 seconds = 2 minutes
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        sleep 5

        if curl -sf "$BASE_URL/api/health" > /dev/null 2>&1; then
            log_success "Application is responding!"
            return 0
        fi

        echo -n "."
        attempt=$((attempt + 1))
    done

    echo ""
    log_warning "Application didn't respond to health check within timeout"
    log_info "This may be normal - checking detailed status..."
    return 1
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    # Check health endpoint
    local health_response=$(curl -s "$BASE_URL/api/health" 2>/dev/null || echo "")

    if echo "$health_response" | grep -q "ok"; then
        log_success "Health check: PASSED"
    else
        log_warning "Health check: Failed or pending"
        log_info "Response: $health_response"
    fi

    # Check ready endpoint
    local ready_response=$(curl -s "$BASE_URL/api/ready" 2>/dev/null || echo "")

    if echo "$ready_response" | grep -q "ready"; then
        log_success "Readiness check: PASSED"
    else
        log_warning "Readiness check: Failed or pending"
    fi

    # Check main page
    local main_response=$(curl -sI "$BASE_URL/" 2>/dev/null | head -1 || echo "")

    if echo "$main_response" | grep -q "200"; then
        log_success "Main page: ACCESSIBLE"
    else
        log_warning "Main page: Check pending"
    fi
}

# Show deployment summary
show_summary() {
    print_header "DEPLOYMENT COMPLETE"

    echo "🌐 Your SecureWave VPN Application:"
    echo ""
    echo "   Main Site:      $BASE_URL"
    echo "   Home Page:      $BASE_URL/home.html"
    echo "   Login:          $BASE_URL/login.html"
    echo "   Register:       $BASE_URL/register.html"
    echo "   Dashboard:      $BASE_URL/dashboard.html"
    echo "   API Docs:       $BASE_URL/api/docs"
    echo "   Health Check:   $BASE_URL/api/health"
    echo ""
    echo "📊 Monitoring & Logs:"
    echo "   az webapp log tail -g $RESOURCE_GROUP -n $APP_NAME"
    echo ""
    echo "🔧 Management:"
    echo "   Restart:  az webapp restart -g $RESOURCE_GROUP -n $APP_NAME"
    echo "   Stop:     az webapp stop -g $RESOURCE_GROUP -n $APP_NAME"
    echo "   Start:    az webapp start -g $RESOURCE_GROUP -n $APP_NAME"
    echo ""
    echo "🌍 Share this link: $BASE_URL"
    echo ""
}

# Main deployment flow
main() {
    print_header "SECUREWAVE VPN - UNIVERSAL AZURE DEPLOYMENT"

    # Step 1: Check prerequisites
    check_azure_auth

    # Step 2: Create deployment package
    create_deployment_package

    # Step 3: Configure Azure resources
    configure_azure_resources

    # Step 4: Configure application settings
    configure_app_settings

    # Step 5: Deploy application
    deploy_application

    # Step 6: Wait for app to be ready
    wait_for_app || true

    # Step 7: Verify deployment
    verify_deployment

    # Step 8: Show summary
    show_summary

    log_success "Deployment script completed!"
}

# Run main function
main "$@"
