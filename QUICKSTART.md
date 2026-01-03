# SecureWave VPN - Quick Start Guide

## Deploy in 3 Steps

### 1. Login to Azure
```bash
az login
```

### 2. Run Deployment Script
```bash
./deploy_production.sh
```

### 3. Access Your App
Open: `https://securewave-web.azurewebsites.net`

---

## Troubleshooting

If something goes wrong:

```bash
./diagnose_and_fix.sh
```

---

## Files Overview

- `deploy_production.sh` - Main deployment script
- `diagnose_and_fix.sh` - Diagnostic and fix tool
- `startup.sh` - Azure startup script
- `Dockerfile.azure` - Azure container configuration

---

## Support

Check logs:
```bash
az webapp log tail -g SecureWaveRG -n securewave-web
```

Restart app:
```bash
az webapp restart -g SecureWaveRG -n securewave-web
```
