# SecureWave VPN - Deployment Status

**Last Updated:** 2026-01-24

---

## Current Deployments

### Production Website
- **URL:** https://securewave-web.azurewebsites.net
- **Branch:** master
- **Status:** Pending v6.0 deployment
- **Platform:** Azure App Service

### Staging Website
- **URL:** https://securewave-staging.azurewebsites.net
- **Branch:** develop
- **Status:** Available

---

## CI/CD Pipeline

### Workflow: ci-cd.yml

The pipeline now includes intelligent change detection:

| Job | Runs When | Status |
|-----|-----------|--------|
| changes | Always | Detects file changes |
| lint | Always (Python lint skipped for UI-only) | Active |
| test | Backend changes only | Conditional |
| security | Backend changes only | Conditional |
| build | lint passes, test/security pass or skipped | Active |
| deploy-production | build passes, master branch | Active |

### UI-Only Changes

When changes are limited to:
- `static/**`
- `templates/**`
- `securewave_app/**`
- `DESIGN_SYSTEM.md`

The pipeline will:
1. Skip Python linting
2. Skip backend tests
3. Skip security scans
4. Proceed directly to build and deploy

---

## Manual Deployment (Fallback)

If CI blocks deployment, use Azure CLI:

```bash
# Login to Azure
az login

# Deploy to production
az webapp deployment source config-zip \
  --resource-group SecureWaveRG \
  --name securewave-web \
  --src ./deploy.zip
```

---

## Verification Steps

After deployment:

1. Check home page loads: `curl https://securewave-web.azurewebsites.net/`
2. Verify CSS loads: Check for lavender colors (#F5EFFF, #A294F9)
3. Check logo displays: Inspect `/img/logo.svg`
4. Test dark mode toggle
5. Verify responsive at 320px, 768px, 1024px

---

## Recent Deployments

| Date | Version | Commit | Status |
|------|---------|--------|--------|
| 2026-01-24 | v6.0 | pending | Awaiting CI |
| 2026-01-23 | v5.1 | b2a7040 | Pushed to GitHub |
| 2026-01-23 | v5.0 | 46dd593 | Superseded |

---

## Contact

For deployment issues, check GitHub Actions logs or Azure Portal.
