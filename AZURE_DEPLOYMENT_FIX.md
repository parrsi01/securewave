# Azure Deployment Fix - UI v1.0

**Date:** 2026-01-25
**Issue:** Phantom deployments - GitHub Actions reports success but files not updated
**Status:** Workflow fixed, credentials need verification

---

## Problem Summary

### What Happened
1. ✅ UI v1.0 code committed (commits `bc1c045`, `331bdf9`)
2. ✅ GitHub Actions workflow ran and reported "Success"
3. ❌ Azure still serving old files (`professional.css` instead of `ui_v1.css`)
4. ❌ New CSS returns 404 on both Azure URLs

### Root Cause
GitHub Actions workflow had **`continue-on-error: true`** on critical deployment steps, causing:
- Deployment failures to be silently ignored
- Workflow to always report success
- No verification that files actually deployed

---

## Fixes Applied

### 1. Removed Silent Failures ✅

**Changed in [.github/workflows/ci-cd.yml](.github/workflows/ci-cd.yml):**

```yaml
# BEFORE (lines 248-259)
- name: Azure Login
  uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
  continue-on-error: true  # ❌ Fails silently

- name: Deploy to Azure Web App (Production)
  uses: azure/webapps-deploy@v2
  with:
    app-name: ${{ env.AZURE_WEBAPP_NAME_PROD }}
    package: .
  continue-on-error: true  # ❌ Fails silently

# AFTER
- name: Azure Login
  uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
  # ✅ Will fail workflow if credentials invalid

- name: Deploy to Azure Web App (Production)
  uses: azure/webapps-deploy@v2
  with:
    app-name: ${{ env.AZURE_WEBAPP_NAME_PROD }}
    package: .
  # ✅ Will fail workflow if deployment fails
```

### 2. Added Deployment Verification ✅

**New verification steps:**

```yaml
- name: Wait for deployment to complete
  run: sleep 45  # Give Azure time to process

- name: Verify static files deployed
  run: |
    # Check ui_v1.css is accessible (HTTP 200)
    # Retry 5 times with 10s intervals
    # Fail workflow if not accessible

- name: Verify HTML files updated
  run: |
    # Check home.html references ui_v1.css
    # Fail workflow if still using old CSS

- name: Run smoke tests
  run: |
    # Test homepage loads (HTTP 200)
    # Test API health check
    # Fail workflow if any test fails
```

### 3. Added Success/Failure Notices ✅

```yaml
- name: Deployment summary
  if: success()
  run: echo "🎉 Deployment successful!"

- name: Deployment failure notice
  if: failure()
  run: echo "❌ Deployment failed - check logs"
```

---

## Azure Credentials Check

### Current Credentials Configuration

The workflow expects this secret in GitHub:

**Secret Name:** `AZURE_CREDENTIALS`

**Expected Format:**
```json
{
  "clientId": "55850cdb-6553-4317-8065-af7c0ba4e399",
  "clientSecret": "<SECRET_VALUE>",
  "subscriptionId": "ca5729a0-9aac-469d-b518-a7e970878993",
  "tenantId": "1e7d59bd-9531-4720-aa64-fe5513491eb1",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

### How to Verify/Update Credentials

#### Option 1: Check GitHub Secrets (Recommended)

1. Go to: `https://github.com/parrsi01/securewave/settings/secrets/actions`
2. Look for secret named: `AZURE_CREDENTIALS`
3. If missing or expired, create new credentials:

```bash
# Via Azure CLI
az ad sp create-for-rbac \
  --name "github-actions-securewave" \
  --role contributor \
  --scopes /subscriptions/ca5729a0-9aac-469d-b518-a7e970878993/resourceGroups/SecureWaveRG \
  --sdk-auth

# Copy the JSON output and save as AZURE_CREDENTIALS secret
```

#### Option 2: Test Credentials Manually

```bash
# Test login with current credentials
az login --service-principal \
  --username 55850cdb-6553-4317-8065-af7c0ba4e399 \
  --password <CLIENT_SECRET> \
  --tenant 1e7d59bd-9531-4720-aa64-fe5513491eb1

# If successful, test deployment permissions
az webapp list --resource-group SecureWaveRG
```

#### Option 3: Create New Service Principal

If credentials are expired or invalid:

```bash
# 1. Login to Azure
az login

# 2. Create new service principal with deployment permissions
az ad sp create-for-rbac \
  --name "github-securewave-deploy" \
  --role "Contributor" \
  --scopes /subscriptions/ca5729a0-9aac-469d-b518-a7e970878993/resourceGroups/SecureWaveRG \
  --sdk-auth > azure-credentials.json

# 3. Copy contents of azure-credentials.json to GitHub secret AZURE_CREDENTIALS
# 4. Delete the local file
rm azure-credentials.json
```

---

## Deployment Target URLs

### Current Configuration

**From [ci-cd.yml](.github/workflows/ci-cd.yml) (lines 21-25):**

```yaml
AZURE_WEBAPP_NAME_PROD: securewave-web
AZURE_WEBAPP_URL_PROD: https://securewave-web.azurewebsites.net
```

### URL Confusion

You mentioned: `https://securewave-vpn.azurewebsites.net`
Workflow deploys to: `https://securewave-web.azurewebsites.net`

**These are DIFFERENT Azure App Services.**

#### To Fix URL Mismatch:

**Option A: Update workflow to deploy to securewave-vpn**
```yaml
# Change lines 21-22 in ci-cd.yml
AZURE_WEBAPP_NAME_PROD: securewave-vpn
AZURE_WEBAPP_URL_PROD: https://securewave-vpn.azurewebsites.net
```

**Option B: Use securewave-web as primary URL**
- Update all documentation to use `securewave-web.azurewebsites.net`
- Consider `securewave-vpn.azurewebsites.net` as legacy/staging

---

## Testing the Fix

### Trigger New Deployment

```bash
# Add empty commit to trigger workflow
git commit --allow-empty -m "Test deployment verification

Testing new GitHub Actions workflow with:
- No silent failures (removed continue-on-error)
- CSS file verification
- HTML update verification
- Smoke tests

If this succeeds, ui_v1.css will be live on Azure.

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin master
```

### Monitor Deployment

1. **GitHub Actions:** `https://github.com/parrsi01/securewave/actions`
2. **Watch for:**
   - ✅ "Azure Login" succeeds
   - ✅ "Deploy to Azure Web App" succeeds
   - ✅ "Verify static files deployed" succeeds
   - ✅ "Verify HTML files updated" succeeds

3. **If any step fails:**
   - Workflow will now **fail loudly** (not silently)
   - Check the failed step's logs for the specific error
   - Most likely issue: Invalid/expired Azure credentials

### Verify Deployment Success

```bash
# After workflow completes successfully:

# 1. Check CSS file is accessible
curl -I https://securewave-web.azurewebsites.net/css/ui_v1.css
# Expected: HTTP/2 200

# 2. Check HTML references new CSS
curl -s https://securewave-web.azurewebsites.net/home.html | grep css
# Expected: href="/css/ui_v1.css?v=20260125"

# 3. Check actual CSS content
curl -s https://securewave-web.azurewebsites.net/css/ui_v1.css | head -20
# Expected: Calm Slate color palette (#475569, #3b82f6)
```

---

## Troubleshooting

### Issue: Azure Login Fails

**Error Message:**
```
Error: Login failed with Error: Az CLI Login failed.
```

**Solution:**
1. Check `AZURE_CREDENTIALS` secret exists in GitHub
2. Verify JSON format is correct (no extra spaces/newlines)
3. Check if service principal still exists: `az ad sp show --id 55850cdb-6553-4317-8065-af7c0ba4e399`
4. Create new service principal if needed (see "Create New Service Principal" above)

### Issue: Deployment Succeeds But Files Not Updated

**Error Message:**
```
❌ ERROR: CSS file still not accessible after 5 attempts
```

**Possible Causes:**
1. **Azure caching issue** - Restart the App Service:
   ```bash
   az webapp restart --name securewave-web --resource-group SecureWaveRG
   ```

2. **Wrong deployment method** - The `package: .` method might not work for Docker apps.
   Consider switching to container registry deployment.

3. **App Service not configured for GitHub Actions** - Check Azure Portal:
   - Go to App Service → Deployment Center
   - Ensure "Source" is set to GitHub Actions
   - Verify workflow file is linked

### Issue: HTML Still References Old CSS

**Error Message:**
```
❌ ERROR: HTML still references old CSS
Found CSS reference: href="/css/professional.css"
```

**Possible Causes:**
1. **Deployment copied old files** - The `.git` directory might have old cached files.
   Add `.dockerignore` to exclude:
   ```
   .git
   .github
   *.md
   tests/
   ```

2. **Azure serving from CDN cache** - If using Azure CDN, purge cache:
   ```bash
   az cdn endpoint purge \
     --resource-group SecureWaveRG \
     --profile-name <CDN_PROFILE> \
     --name <CDN_ENDPOINT> \
     --content-paths "/*"
   ```

---

## Next Steps

1. **Commit the workflow fix:**
   ```bash
   git add .github/workflows/ci-cd.yml AZURE_DEPLOYMENT_FIX.md
   git commit -m "Fix GitHub Actions deployment - remove silent failures"
   git push origin master
   ```

2. **Monitor the deployment:**
   - Watch GitHub Actions workflow
   - If it fails, check which step failed
   - Use error message to diagnose credentials or configuration

3. **If credentials are the issue:**
   - Generate new service principal (see instructions above)
   - Update GitHub secret `AZURE_CREDENTIALS`
   - Re-run workflow

4. **Verify UI is live:**
   - Visit `https://securewave-web.azurewebsites.net/home.html`
   - Should see new Calm Slate design (slate/blue colors)
   - Should NOT see legacy palette colors

---

## Summary

✅ **Fixed:** Removed `continue-on-error` from deployment steps
✅ **Added:** CSS file verification (checks HTTP 200)
✅ **Added:** HTML update verification (checks ui_v1.css reference)
✅ **Added:** Smoke tests (homepage + API health)
❓ **Needs Check:** Azure credentials validity
❓ **Needs Clarification:** Which URL is primary (securewave-web vs securewave-vpn)

**The code is ready. The workflow is fixed. Now we need valid Azure credentials to actually deploy.**
