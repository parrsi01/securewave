# SecureWave VPN - Deployment Status

**Last Updated:** 2026-01-24
**UI Version:** v6.0 (Lavender Light Theme)
**CI Status:** PASSING

---

## Current State

| Component | Status | Notes |
|-----------|--------|-------|
| GitHub Repo | Current | master branch has UI v6.0 |
| CI Pipeline | PASSING | Run #21319746585 |
| Docker Build | PASSING | Dockerfile fixed |
| Azure Site | OUTDATED | Serving old Ocean Teal theme |
| Deployment | BLOCKED | Missing AZURE_CREDENTIALS secret |

---

## OPTION A: Automated Deployment (GitHub Actions)

### Required Secret: AZURE_CREDENTIALS

Add this secret to GitHub repository settings:
**Settings > Secrets and variables > Actions > New repository secret**

**Name:** `AZURE_CREDENTIALS`

**Value format (JSON):**
```json
{
  "clientId": "55850cdb-6553-4317-8065-af7c0ba4e399",
  "clientSecret": "<YOUR_SERVICE_PRINCIPAL_SECRET>",
  "subscriptionId": "ca5729a0-9aac-469d-b518-a7e970878993",
  "tenantId": "1e7d59bd-9531-4720-aa64-fe5513491eb1"
}
```

### How to get the client secret:

```bash
# Option 1: Create new service principal
az ad sp create-for-rbac --name "securewave-deploy" \
  --role contributor \
  --scopes /subscriptions/ca5729a0-9aac-469d-b518-a7e970878993/resourceGroups/SecureWaveRG \
  --sdk-auth

# Option 2: Reset existing service principal password
az ad sp credential reset --id 55850cdb-6553-4317-8065-af7c0ba4e399
```

### Trigger Deployment:

Once secret is configured:
1. Push any commit to master branch, OR
2. Go to Actions > CI/CD Pipeline > Run workflow

---

## OPTION B: Manual Deployment (Azure CLI)

### Prerequisites:
```bash
# Install Azure CLI if not present
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login
```

### Step 1: Create deployment package
```bash
cd /home/sp/cyber-course/projects/securewave

# Create zip excluding unnecessary files
zip -r deploy.zip . \
  -x "*.git*" \
  -x "securewave_app/*" \
  -x "*.pyc" \
  -x "__pycache__/*" \
  -x "*.zip" \
  -x "azure-logs*" \
  -x "app-logs*" \
  -x ".claude/*" \
  -x "*.md" \
  -x "tests/*"
```

### Step 2: Deploy to Azure
```bash
# Deploy the zip file
az webapp deployment source config-zip \
  --resource-group SecureWaveRG \
  --name securewave-web \
  --src deploy.zip

# OR use the webapp deploy command
az webapp deploy \
  --resource-group SecureWaveRG \
  --name securewave-web \
  --src-path deploy.zip \
  --type zip
```

### Step 3: Restart the app (if needed)
```bash
az webapp restart \
  --resource-group SecureWaveRG \
  --name securewave-web
```

---

## Verification Checklist

After deployment, verify:

### 1. CSS Lavender Palette
```bash
curl -s https://securewave-web.azurewebsites.net/css/professional.css | grep -E "#F5EFFF|#A294F9"
```
Expected: Should find lavender color tokens

### 2. Logo Assets
```bash
curl -sI https://securewave-web.azurewebsites.net/img/logo.svg
curl -sI https://securewave-web.azurewebsites.net/favicon.svg
```
Expected: HTTP 200 responses

### 3. Health Check
```bash
curl -s https://securewave-web.azurewebsites.net/api/health
```
Expected: `{"status":"healthy"}`

### 4. Homepage Load
```bash
curl -s https://securewave-web.azurewebsites.net/ | head -20
```
Expected: HTML with SecureWave content

---

## CI/CD Pipeline Overview

```
┌─────────┐     ┌──────────┐     ┌─────────┐     ┌────────────────┐
│  lint   │────>│  build   │────>│ deploy  │────>│ Azure Web App  │
│ (pass)  │     │ (Docker) │     │ (prod)  │     │ securewave-web │
└─────────┘     └──────────┘     └─────────┘     └────────────────┘
     │
     v
┌──────────┐  ┌────────────┐
│   test   │  │  security  │  (non-blocking)
│ (skip OK)│  │ (skip OK)  │
└──────────┘  └────────────┘
```

---

## Recent Commits

| Commit | Message | Date |
|--------|---------|------|
| 9639af4 | Remove templates/ from Dockerfile | 2026-01-24 |
| 15516d5 | Fix Dockerfiles - use correct static directory path | 2026-01-24 |
| e948629 | Fix CI pipeline - simplify job dependencies | 2026-01-24 |
| 1e47275 | UI v6.0 - CI improvements and documentation | 2026-01-24 |
| 1a24448 | Fix CI plan copy check to match current copy | 2026-01-24 |
| b2a7040 | UI v5.1 - Lavender light theme brand palette | 2026-01-24 |

---

## Troubleshooting

### CI fails at lint step
- Check `scripts/check_plan_copy.sh` assertions
- Ensure plan copy text exists in referenced files

### Docker build fails
- Verify `static/` directory exists
- Check Dockerfile COPY paths

### Azure deploy fails silently
- Verify AZURE_CREDENTIALS secret is set
- Check GitHub Actions logs for auth errors
- Try manual deployment with az CLI

### Site shows old CSS
- Clear browser cache
- Purge Azure CDN (if configured)
- Verify deployment actually ran

---

## Contact

- GitHub: parrsi01/securewave
- Azure Portal: SecureWaveRG resource group
