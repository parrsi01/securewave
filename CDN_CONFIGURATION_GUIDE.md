# CDN Configuration Guide for SecureWave VPN

## Overview

This guide explains how to configure Azure CDN (Content Delivery Network) for SecureWave VPN to improve performance, reduce latency, and provide global content distribution.

## Table of Contents

1. [Why Use CDN?](#why-use-cdn)
2. [Azure CDN Setup](#azure-cdn-setup)
3. [CDN Profile Configuration](#cdn-profile-configuration)
4. [Endpoint Configuration](#endpoint-configuration)
5. [Custom Domain & SSL](#custom-domain--ssl)
6. [Caching Rules](#caching-rules)
7. [Performance Optimization](#performance-optimization)
8. [Monitoring & Analytics](#monitoring--analytics)
9. [Troubleshooting](#troubleshooting)

---

## Why Use CDN?

### Benefits

- **Reduced Latency**: Content served from edge locations closest to users
- **Improved Performance**: Faster page load times and better user experience
- **Bandwidth Savings**: Reduced load on origin server
- **DDoS Protection**: Built-in protection against distributed attacks
- **Global Scalability**: Handle traffic spikes and global users
- **SSL/TLS Offloading**: CDN handles SSL termination

### Use Cases for SecureWave VPN

- Static assets (CSS, JavaScript, images)
- Frontend web application files
- VPN configuration downloads
- API responses with caching headers
- Large file downloads (WireGuard configs, installers)

---

## Azure CDN Setup

### Prerequisites

- Azure subscription
- SecureWave VPN deployed to Azure App Service
- Azure CLI installed (optional)

### Step 1: Create CDN Profile

#### Using Azure Portal

1. Log in to [Azure Portal](https://portal.azure.com)
2. Click "Create a resource"
3. Search for "CDN" and select "Front Door and CDN profiles"
4. Click "Create"
5. Fill in the details:
   - **Subscription**: Your Azure subscription
   - **Resource Group**: Same as SecureWave VPN (e.g., `securewave-rg`)
   - **Name**: `securewave-cdn`
   - **Region**: Same as your app service
   - **Pricing Tier**:
     - **Standard Microsoft**: $0.087/GB (recommended for most use cases)
     - **Standard Akamai**: Better performance, higher cost
     - **Standard Verizon**: Enterprise features
     - **Premium Verizon**: Advanced rules engine
6. Click "Review + Create"
7. Click "Create"

#### Using Azure CLI

```bash
# Login to Azure
az login

# Set variables
RESOURCE_GROUP="securewave-rg"
CDN_PROFILE_NAME="securewave-cdn"
LOCATION="eastus"

# Create CDN profile
az cdn profile create \
  --resource-group $RESOURCE_GROUP \
  --name $CDN_PROFILE_NAME \
  --sku Standard_Microsoft \
  --location $LOCATION
```

---

## CDN Profile Configuration

### Step 2: Create CDN Endpoint

#### Using Azure Portal

1. Navigate to your CDN profile
2. Click "Add an endpoint"
3. Fill in the details:
   - **Name**: `securewave` (results in `securewave.azureedge.net`)
   - **Origin type**: Web App
   - **Origin hostname**: `securewave.azurewebsites.net` (your app service)
   - **Origin path**: Leave blank
   - **Origin host header**: `securewave.azurewebsites.net`
   - **Protocol**: HTTPS only
   - **Origin port**: 443
   - **Optimized for**: General web delivery
4. Click "Add"

#### Using Azure CLI

```bash
# Set variables
ENDPOINT_NAME="securewave"
ORIGIN_HOSTNAME="securewave.azurewebsites.net"

# Create CDN endpoint
az cdn endpoint create \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --name $ENDPOINT_NAME \
  --origin $ORIGIN_HOSTNAME \
  --origin-host-header $ORIGIN_HOSTNAME \
  --enable-compression true \
  --content-types-to-compress \
    "text/html" \
    "text/css" \
    "application/javascript" \
    "application/json" \
    "image/svg+xml"
```

---

## Endpoint Configuration

### Compression Settings

Enable compression for better performance:

1. Navigate to CDN endpoint
2. Click "Compression"
3. Enable compression
4. Add MIME types:
   - `text/html`
   - `text/css`
   - `text/javascript`
   - `application/javascript`
   - `application/json`
   - `application/xml`
   - `image/svg+xml`
   - `font/woff`
   - `font/woff2`

### Query String Caching

Configure how query strings affect caching:

1. Navigate to CDN endpoint
2. Click "Caching rules"
3. Select **Query string caching behavior**:
   - **Ignore query strings**: Cache one version (recommended for static assets)
   - **Bypass caching**: Don't cache URLs with query strings (for dynamic content)
   - **Cache every unique URL**: Cache different versions for each query string

### HTTP/HTTPS Settings

1. Navigate to CDN endpoint
2. Click "Custom domain" (after adding custom domain)
3. Enable **HTTPS**
4. Select certificate type:
   - **CDN managed**: Free, auto-renewing certificate
   - **Custom certificate**: Your own certificate from Key Vault

---

## Custom Domain & SSL

### Add Custom Domain

#### Prerequisites

- Custom domain configured with CNAME record pointing to CDN endpoint
- Example: `cdn.vpn.example.com` -> `securewave.azureedge.net`

#### Steps

1. Add DNS CNAME record at your domain registrar:
   ```
   Type: CNAME
   Host: cdn
   Value: securewave.azureedge.net
   TTL: 3600
   ```

2. In Azure Portal:
   - Navigate to CDN endpoint
   - Click "Custom domains"
   - Click "Add custom domain"
   - Enter: `cdn.vpn.example.com`
   - Click "Add"

3. Enable HTTPS:
   - Click on the custom domain
   - Enable "Custom domain HTTPS"
   - Select "CDN managed"
   - Click "Save"
   - Wait 6-8 hours for certificate provisioning

#### Using Azure CLI

```bash
# Add custom domain
CUSTOM_DOMAIN="cdn.vpn.example.com"

az cdn custom-domain create \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --endpoint-name $ENDPOINT_NAME \
  --name cdn-custom \
  --hostname $CUSTOM_DOMAIN

# Enable HTTPS
az cdn custom-domain enable-https \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --endpoint-name $ENDPOINT_NAME \
  --name cdn-custom
```

---

## Caching Rules

### Global Caching Rules

Set default caching behavior for all content:

1. Navigate to CDN endpoint
2. Click "Caching rules"
3. Set **Global caching rules**:
   - **Query string caching**: Ignore query strings
   - **Caching behavior**: Override
   - **Cache expiration duration**: 1 day

### Custom Caching Rules

Create rules for specific file types:

#### Static Assets (Long Cache)

```
Path pattern: /static/*
Cache behavior: Override
Cache duration: 365 days
```

#### HTML Files (Short Cache)

```
Path pattern: /*.html
Cache behavior: Override
Cache duration: 1 hour
```

#### API Responses (No Cache)

```
Path pattern: /api/*
Cache behavior: Bypass cache
```

#### JavaScript & CSS (Medium Cache)

```
Path pattern: *.js
Cache behavior: Override
Cache duration: 7 days

Path pattern: *.css
Cache behavior: Override
Cache duration: 7 days
```

### Using Azure CLI

```bash
# Add caching rule for static assets
az cdn endpoint rule add \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --endpoint-name $ENDPOINT_NAME \
  --order 1 \
  --rule-name "StaticAssets" \
  --match-variable UrlPath \
  --operator BeginsWith \
  --match-values "/static/" \
  --action-name CacheExpiration \
  --cache-behavior Override \
  --cache-duration "365.00:00:00"
```

---

## Performance Optimization

### 1. Enable Compression

Already covered in [Endpoint Configuration](#compression-settings)

### 2. Optimize Images

Use CDN image transformation features:

```html
<!-- Original image -->
<img src="https://cdn.vpn.example.com/images/hero.jpg" />

<!-- Optimized with query parameters (if supported by CDN tier) -->
<img src="https://cdn.vpn.example.com/images/hero.jpg?width=800&quality=85&format=webp" />
```

### 3. Implement Cache-Control Headers

In your application, set appropriate cache headers:

```python
# main.py - Add cache headers to static files
from fastapi.responses import FileResponse

@app.get("/static/{file_path:path}")
async def serve_static(file_path: str):
    # Set cache headers
    headers = {
        "Cache-Control": "public, max-age=31536000, immutable",  # 1 year
        "X-Content-Type-Options": "nosniff",
    }
    return FileResponse(f"static/{file_path}", headers=headers)
```

### 4. Purge CDN Cache

Manually purge cache after deployments:

```bash
# Purge entire endpoint
az cdn endpoint purge \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --name $ENDPOINT_NAME \
  --content-paths "/*"

# Purge specific paths
az cdn endpoint purge \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --name $ENDPOINT_NAME \
  --content-paths "/static/css/*" "/static/js/*"
```

### 5. Preload Popular Content

Preload frequently accessed files:

```bash
az cdn endpoint load \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --name $ENDPOINT_NAME \
  --content-paths \
    "/index.html" \
    "/static/css/global.css" \
    "/static/js/main.js"
```

---

## Monitoring & Analytics

### Azure Monitor

1. Navigate to CDN profile
2. Click "Metrics"
3. Add metrics:
   - **Total Requests**: Track traffic volume
   - **Bandwidth**: Monitor data transfer
   - **Cache Hit Ratio**: Measure caching efficiency (target: >80%)
   - **Origin Latency**: Track backend performance
   - **Error Rate**: Monitor 4xx/5xx errors

### Diagnostic Logs

Enable diagnostic logging:

1. Navigate to CDN profile
2. Click "Diagnostic settings"
3. Click "Add diagnostic setting"
4. Select logs to collect:
   - **Access logs**: All CDN requests
   - **Core analytics**: Performance metrics
5. Send to:
   - Log Analytics workspace
   - Storage account
   - Event Hub

### Application Insights Integration

```python
# main.py - Track CDN usage
from applicationinsights import TelemetryClient

tc = TelemetryClient('<instrumentation-key>')

@app.middleware("http")
async def track_cdn_usage(request: Request, call_next):
    # Check if request came through CDN
    cdn_headers = request.headers.get("X-Azure-CDN")

    if cdn_headers:
        tc.track_event("CDN_Hit", {"path": request.url.path})
    else:
        tc.track_event("Origin_Hit", {"path": request.url.path})

    return await call_next(request)
```

---

## Troubleshooting

### Issue 1: High Cache Miss Rate

**Symptoms**: Cache hit ratio < 50%

**Solutions**:
- Check caching rules are configured correctly
- Verify origin is setting proper `Cache-Control` headers
- Ensure query strings aren't preventing caching
- Review if content is truly cacheable

### Issue 2: Stale Content

**Symptoms**: Users see old version after deployment

**Solutions**:
```bash
# Purge CDN cache after deployments
az cdn endpoint purge \
  --resource-group $RESOURCE_GROUP \
  --profile-name $CDN_PROFILE_NAME \
  --name $ENDPOINT_NAME \
  --content-paths "/*"
```

### Issue 3: Custom Domain SSL Not Working

**Symptoms**: HTTPS certificate errors on custom domain

**Solutions**:
- Wait 6-8 hours for certificate provisioning
- Verify CNAME record is correct
- Check DNS propagation: `dig cdn.vpn.example.com`
- Ensure domain validation succeeded

### Issue 4: Origin Connection Errors

**Symptoms**: 502/503 errors from CDN

**Solutions**:
- Verify origin server is accessible
- Check origin hostname is correct
- Ensure origin is responding to CDN requests
- Review origin health in Azure Portal

### Issue 5: Compression Not Working

**Symptoms**: Large file sizes despite enabling compression

**Solutions**:
- Verify MIME types are configured
- Check origin isn't already compressing (double compression)
- Ensure `Accept-Encoding: gzip` header is sent
- Review CDN compression logs

---

## Best Practices

### 1. Security

- ✅ Enable HTTPS only
- ✅ Use CDN managed certificates
- ✅ Configure WAF rules (Premium tier)
- ✅ Enable DDoS protection
- ✅ Implement rate limiting for API endpoints

### 2. Performance

- ✅ Set appropriate cache durations
- ✅ Enable compression for text-based files
- ✅ Optimize images before uploading
- ✅ Use versioning for static assets (`style.v2.css`)
- ✅ Implement lazy loading for images

### 3. Cost Optimization

- ✅ Monitor bandwidth usage
- ✅ Set appropriate cache durations to reduce origin requests
- ✅ Use Standard tier unless Premium features needed
- ✅ Purge cache selectively, not entire endpoint
- ✅ Consider reserved capacity for predictable workloads

### 4. Maintenance

- ✅ Automate cache purging in CI/CD pipeline
- ✅ Monitor cache hit ratios weekly
- ✅ Review and optimize caching rules quarterly
- ✅ Test CDN configuration in staging environment
- ✅ Keep documentation updated

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
# .github/workflows/deploy-and-purge-cdn.yml
name: Deploy and Purge CDN

on:
  push:
    branches: [main]

jobs:
  deploy-and-purge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy to Azure
        # ... deployment steps ...

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Purge CDN Cache
        run: |
          az cdn endpoint purge \
            --resource-group securewave-rg \
            --profile-name securewave-cdn \
            --name securewave \
            --content-paths "/*"

      - name: Preload Critical Assets
        run: |
          az cdn endpoint load \
            --resource-group securewave-rg \
            --profile-name securewave-cdn \
            --name securewave \
            --content-paths \
              "/index.html" \
              "/static/css/global.css" \
              "/static/js/main.js"
```

---

## Cost Estimation

### Pricing Tiers (as of 2024)

**Standard Microsoft CDN**:
- First 10 TB/month: $0.087/GB
- Next 40 TB/month: $0.065/GB
- Next 100 TB/month: $0.043/GB
- Over 150 TB/month: $0.025/GB

**Additional Costs**:
- HTTPS requests: $0.010 per 10,000 requests
- SSL certificate: Free (CDN managed)

### Example Monthly Cost

For a VPN service with:
- 10,000 users
- 100 MB average transfer per user
- Total: 1 TB/month

**Estimated Cost**: ~$87/month

---

## Next Steps

1. ✅ Create CDN profile
2. ✅ Configure endpoint
3. ✅ Add custom domain
4. ✅ Enable HTTPS
5. ✅ Set caching rules
6. ✅ Enable monitoring
7. ✅ Test performance
8. ✅ Integrate with CI/CD
9. ✅ Optimize based on metrics

## Support Resources

- [Azure CDN Documentation](https://docs.microsoft.com/azure/cdn/)
- [Azure CDN Pricing](https://azure.microsoft.com/pricing/details/cdn/)
- [Azure CDN CLI Reference](https://docs.microsoft.com/cli/azure/cdn)
- [Azure Support](https://azure.microsoft.com/support/)

---

**Document Version**: 1.0
**Last Updated**: 2024-01-07
**Maintained By**: SecureWave DevOps Team
