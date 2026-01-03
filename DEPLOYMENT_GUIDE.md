# SecureWave VPN - Production Deployment Guide

## 🚀 Quick Start

Deploy SecureWave VPN to Azure in minutes with the automated deployment script:

```bash
./deploy_production.sh
```

Your application will be live at: `https://securewave-web.azurewebsites.net`

---

## 📋 Prerequisites

### Required Tools

1. **Azure CLI** (version 2.50+)
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

2. **Python 3.12+**
   ```bash
   python3 --version
   ```

3. **zip utility**
   ```bash
   sudo apt-get install zip
   ```

### Azure Account Setup

1. Login to Azure:
   ```bash
   az login
   ```

2. Set your subscription (if you have multiple):
   ```bash
   az account set --subscription "YOUR_SUBSCRIPTION_NAME"
   ```

---

## 🎯 Deployment Options

### Option 1: One-Click Deployment (Recommended)

Use the automated production deployment script:

```bash
./deploy_production.sh
```

**Expected deployment time:** 5-10 minutes

---

## 🔧 Configuration

### Key Environment Variables

- `PORT=8000` - Application port
- `DATABASE_URL=sqlite:////tmp/securewave.db` - Database path
- `PYTHONPATH=/home/site/wwwroot` - Python module path
- `WG_MOCK_MODE=true` - WireGuard mock mode
- `ENVIRONMENT=production` - Environment mode

---

## 🔍 Monitoring & Diagnostics

### Diagnostic Script

```bash
./diagnose_and_fix.sh       # Interactive menu
./diagnose_and_fix.sh health # Health checks
./diagnose_and_fix.sh logs   # View logs
./diagnose_and_fix.sh fix    # Restart app
```

### View Logs

```bash
az webapp log tail -g SecureWaveRG -n securewave-web
```

---

## 📱 Access Your Application

- **Home:** `https://securewave-web.azurewebsites.net/home.html`
- **Login:** `https://securewave-web.azurewebsites.net/login.html`
- **Dashboard:** `https://securewave-web.azurewebsites.net/dashboard.html`
- **API Docs:** `https://securewave-web.azurewebsites.net/api/docs`

---

## ✅ Deployment Complete!

**Last Updated:** 2026-01-02
