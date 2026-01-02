# SecureWave VPN - Production Deployment Checklist

This checklist ensures all security and infrastructure requirements are met before and after deployment.

## Pre-Deployment Checklist

### Security Configuration
- [ ] JWT secrets generated and set in Azure App Service
  ```bash
  az webapp config appsettings set --name securewave-app --resource-group SecureWaveRG \
    --settings ACCESS_TOKEN_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')"
  ```
- [ ] ENVIRONMENT set to `production`
- [ ] CORS_ORIGINS configured with actual domain (no wildcards)
- [ ] WG_ENCRYPTION_KEY generated and set
- [ ] Database credentials secured
- [ ] Payment API keys (Stripe, PayPal) configured

### Code Review
- [ ] All TODO comments reviewed
- [ ] No hardcoded secrets in code
- [ ] .env files not committed to git
- [ ] Logging configured appropriately (no sensitive data logged)

### Database
- [ ] Alembic migrations created
- [ ] Migrations tested locally
- [ ] Database backup created
- [ ] Migration rollback plan documented

### Infrastructure Scripts
- [ ] All `.sh` scripts have execute permissions (`chmod +x`)
- [ ] Azure CLI authenticated (`az login`)
- [ ] Resource group exists
- [ ] Container registry accessible

---

## Deployment Steps

### 1. Generate Migrations
```bash
# Create migrations for new models
alembic revision --autogenerate -m "add_audit_and_vpn_infrastructure"

# Review the generated migration file
cat alembic/versions/*_add_audit_and_vpn_infrastructure.py

# Test migrations locally
alembic upgrade head
```

### 2. Make Scripts Executable
```bash
chmod +x quick_redeploy.sh
chmod +x infrastructure/deploy_vpn_server.sh
chmod +x infrastructure/health_check.sh
chmod +x infrastructure/init_demo_servers.py
chmod +x infrastructure/register_server.py
```

### 3. Deploy to Production
```bash
# Run the comprehensive deployment script
./quick_redeploy.sh
```

---

## Post-Deployment Verification

### Security Checks
- [ ] Rate limiting returns 429 after threshold
  ```bash
  for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" https://securewave-app.azurewebsites.net/api/health; done
  ```
- [ ] CORS rejects unauthorized origins
  ```bash
  curl -I -H "Origin: https://evil.com" https://securewave-app.azurewebsites.net/api/health | grep Access-Control
  ```
- [ ] Security headers present
  ```bash
  curl -I https://securewave-app.azurewebsites.net/ | grep -E "X-Content-Type|X-Frame|X-XSS"
  ```
- [ ] Password reset endpoint removed (returns 404/405)
  ```bash
  curl -X POST https://securewave-app.azurewebsites.net/api/auth/reset-password
  ```
- [ ] JWT secrets not using defaults (check Azure App Settings)

### VPN Infrastructure
- [ ] VPN servers loaded in database
  ```bash
  curl https://securewave-app.azurewebsites.net/api/optimizer/servers | jq
  ```
- [ ] Real server (us-east-1) marked as "active"
- [ ] Demo servers marked as "demo"
- [ ] Health monitor running (check logs)
- [ ] VPN config generation works
  ```bash
  # Test with valid JWT token
  curl -X POST https://securewave-app.azurewebsites.net/api/vpn/generate \
    -H "Authorization: Bearer <token>" \
    -H "Content-Type: application/json" \
    -d '{}'
  ```

### Functional Tests
- [ ] User registration works
- [ ] User login returns JWT tokens
- [ ] Token refresh works
- [ ] Dashboard loads user info
- [ ] VPN config download works
- [ ] QR code generation works
- [ ] Connection quality reporting works
- [ ] Audit logs being created

### Performance
- [ ] API response times < 500ms
- [ ] Health endpoint responds < 100ms
- [ ] Database queries optimized (check slow query log)
- [ ] Background tasks running (health monitor)

### Monitoring
- [ ] Application logs accessible
  ```bash
  az webapp log tail --name securewave-app --resource-group SecureWaveRG
  ```
- [ ] No critical errors in logs
- [ ] Health monitor updating server metrics
- [ ] Optimizer stats available
  ```bash
  curl https://securewave-app.azurewebsites.net/api/optimizer/stats | jq
  ```

---

## Rollback Plan

If deployment fails, rollback using previous image:

```bash
# List recent images
az acr repository show-tags --name securewaveacr1767120370 --repository securewave --orderby time_desc --output table

# Rollback to previous image
PREVIOUS_TAG="<previous-tag>"
az webapp config container set \
  --name securewave-app \
  --resource-group SecureWaveRG \
  --container-image-name "securewaveacr1767120370.azurecr.io/securewave:$PREVIOUS_TAG"

az webapp restart --name securewave-app --resource-group SecureWaveRG
```

For database rollback:
```bash
# Downgrade one version
alembic downgrade -1

# Or to specific version
alembic downgrade <revision>
```

---

## Known Issues & Limitations

### Current Deployment (Hybrid Mode)
- **1 real VPN server**: us-east-1 (New York) on Azure Container Instance
- **5 demo servers**: Simulate other locations with realistic metrics
- Demo servers have endpoints but don't accept actual VPN connections
- Users can generate configs for demo servers, but only us-east-1 will work

### Scaling Path
To add more real servers:
```bash
# Deploy additional servers
bash infrastructure/deploy_vpn_server.sh us-west-1 westus "San Francisco"
bash infrastructure/deploy_vpn_server.sh eu-west-1 ukwest "London"
```

Cost: ~$10-15/month per additional server

---

## Support & Troubleshooting

### Common Issues

**Issue**: Migrations fail
**Solution**: Check database connectivity and permissions. Run migrations manually:
```bash
az webapp ssh --name securewave-app --resource-group SecureWaveRG
cd /app && alembic upgrade head
```

**Issue**: No VPN servers in database
**Solution**: Initialize demo servers:
```bash
python3 infrastructure/init_demo_servers.py
```

**Issue**: Rate limiting too aggressive
**Solution**: Adjust limits in main.py or set REDIS_URL for distributed rate limiting

**Issue**: VPN config generation fails
**Solution**: Check optimizer stats and server availability:
```bash
curl https://securewave-app.azurewebsites.net/api/optimizer/stats | jq
curl https://securewave-app.azurewebsites.net/api/optimizer/servers | jq
```

### Logs

**Application Logs**:
```bash
az webapp log tail --name securewave-app --resource-group SecureWaveRG
```

**Container Logs** (VPN Server):
```bash
az container logs --resource-group SecureWaveRG --name securewave-vpn-us-east-1
```

**Download Logs**:
```bash
az webapp log download --name securewave-app --resource-group SecureWaveRG --log-file logs.zip
```

---

## Success Criteria

Deployment is successful when:

1. ✅ All security headers present
2. ✅ Rate limiting active
3. ✅ CORS properly restricted
4. ✅ JWT secrets configured
5. ✅ Password reset endpoint removed
6. ✅ Database migrations applied
7. ✅ VPN servers in database (≥1)
8. ✅ Health monitor running
9. ✅ Optimizer initialized
10. ✅ All health checks pass
11. ✅ Users can register and login
12. ✅ VPN configs can be generated
13. ✅ Audit logs being created
14. ✅ Background tasks running

---

## Maintenance

### Regular Tasks
- **Daily**: Check error logs for issues
- **Weekly**: Review audit logs for suspicious activity
- **Monthly**: Review server metrics and optimize
- **Quarterly**: Security audit and dependency updates

### Server Management
```bash
# Add new server
bash infrastructure/deploy_vpn_server.sh <server-id> <region> "<location>"

# Check server status
curl https://securewave-app.azurewebsites.net/api/optimizer/servers | jq '.servers[] | {id: .server_id, status: .status, health: .health_status}'

# Remove server (Azure Container)
az container delete --resource-group SecureWaveRG --name securewave-vpn-<server-id> --yes

# Remove server (Database)
# TODO: Add admin endpoint for server management
```

---

## Contact & Documentation

- **API Documentation**: https://securewave-app.azurewebsites.net/api/docs
- **Health Check**: https://securewave-app.azurewebsites.net/api/health
- **Deployment Guide**: See `VPN_TESTING_GUIDE.md`
- **Environment Template**: See `.env.template`

---

**Last Updated**: 2026-01-01
**Deployment Version**: production-ready-v1.0
