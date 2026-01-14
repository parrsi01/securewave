# SecureWave VPN - Quick Setup Guide

This guide will help you set up and test the new authentication and security features.

## Prerequisites

- Python 3.12+
- PostgreSQL database
- SMTP server access (Gmail, SendGrid, etc.)
- (Optional) Azure account for Key Vault
- (Optional) Domain name for SSL certificates

---

## 1. Install Dependencies

```bash
# Activate virtual environment
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Install dependencies
pip install -r requirements.txt
```

---

## 2. Configure Environment Variables

Create or update `.env` file:

```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/securewave
POSTGRES_PASSWORD=your_password

# JWT Secrets
SECRET_KEY=your-secret-key-here
JWT_SECRET_KEY=your-jwt-secret-key-here

# Email/SMTP Configuration
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM_EMAIL=noreply@securewave.com
SMTP_FROM_NAME=SecureWave VPN
APP_URL=http://localhost:8000

# Payment Providers
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

PAYPAL_CLIENT_ID=your_paypal_client_id
PAYPAL_CLIENT_SECRET=your_paypal_secret
PAYPAL_MODE=sandbox

# Rate Limiting
REDIS_URL=memory://

# Development
ENVIRONMENT=development
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
```

### Gmail SMTP Setup

1. Enable 2FA on your Gmail account
2. Generate an App Password: https://myaccount.google.com/apppasswords
3. Use the app password in `SMTP_PASSWORD`

---

## 3. Run Database Migration

```bash
# Upgrade database to latest schema
alembic upgrade head
```

This will add all the new authentication fields to the `users` table.

---

## 4. Start the Application

```bash
# Development server with auto-reload
python main.py

# Or use uvicorn directly
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The API will be available at:
- API: http://localhost:8000
- Docs: http://localhost:8000/api/docs
- Health: http://localhost:8000/api/health

---

## 5. Test Authentication Features

### A. Test Email Verification

1. **Register a new user:**
```bash
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123"
  }'
```

Expected response:
```json
{
  "message": "Registration successful. Please check your email to verify your account.",
  "email": "test@example.com",
  "email_sent": true,
  "user_id": 1
}
```

2. **Check your email** for the verification link

3. **Verify email** (use token from email):
```bash
curl -X POST http://localhost:8000/api/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{
    "token": "your-verification-token-here"
  }'
```

### B. Test Login

```bash
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123"
  }'
```

Expected response:
```json
{
  "access_token": "eyJ0eXAiOiJKV1...",
  "refresh_token": "eyJ0eXAiOiJKV1...",
  "token_type": "bearer",
  "requires_2fa": false
}
```

### C. Test Password Reset

1. **Request password reset:**
```bash
curl -X POST http://localhost:8000/api/auth/password-reset/request \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com"
  }'
```

2. **Check your email** for the reset link

3. **Reset password** (use token from email):
```bash
curl -X POST http://localhost:8000/api/auth/password-reset/confirm \
  -H "Content-Type: application/json" \
  -d '{
    "token": "your-reset-token-here",
    "new_password": "NewSecurePassword456"
  }'
```

### D. Test Two-Factor Authentication

1. **Get access token** (login first)

2. **Set up 2FA:**
```bash
curl -X POST http://localhost:8000/api/auth/2fa/setup \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

Response includes:
- `secret`: TOTP secret key
- `provisioning_uri`: URI for QR code
- `backup_codes`: Recovery codes (save these!)
- `qr_code_url`: URL to get QR code image

3. **Get QR code:**
```bash
curl -X GET http://localhost:8000/api/auth/2fa/qr \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  --output qr.png
```

4. **Scan QR code** with Google Authenticator or Authy

5. **Verify and enable 2FA:**
```bash
curl -X POST http://localhost:8000/api/auth/2fa/verify \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "totp_code": "123456"
  }'
```

6. **Login with 2FA:**
```bash
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123",
    "totp_code": "123456"
  }'
```

---

## 6. Test Payment Features

### A. Get Available Plans

```bash
curl -X GET http://localhost:8000/api/billing/plans
```

### B. Create Subscription (Stripe)

```bash
curl -X POST http://localhost:8000/api/billing/subscriptions \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "plan_id": "basic",
    "billing_cycle": "monthly",
    "provider": "stripe",
    "payment_method_id": "pm_card_visa"
  }'
```

### C. Get Current Subscription

```bash
curl -X GET http://localhost:8000/api/billing/subscriptions/current \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

---

## 7. Azure Key Vault Setup (Production)

### Create Key Vault

```bash
# Login to Azure
az login

# Create resource group (if needed)
az group create --name securewave-rg --location eastus

# Create Key Vault
az keyvault create \
  --name securewave-vault \
  --resource-group securewave-rg \
  --location eastus
```

### Add Secrets

```bash
# Database URL
az keyvault secret set \
  --vault-name securewave-vault \
  --name DATABASE-URL \
  --value "postgresql://user:pass@host:5432/db"

# Stripe API Key
az keyvault secret set \
  --vault-name securewave-vault \
  --name STRIPE-SECRET-KEY \
  --value "sk_live_..."

# JWT Secret
az keyvault secret set \
  --vault-name securewave-vault \
  --name JWT-SECRET-KEY \
  --value "your-jwt-secret"

# Add all other secrets...
```

### Enable in Application

Update `.env.production`:

```bash
USE_AZURE_KEY_VAULT=true
AZURE_KEY_VAULT_URL=https://securewave-vault.vault.azure.net/
```

### Grant Access to App Service

```bash
# Enable managed identity on your App Service
az webapp identity assign \
  --name securewave-app \
  --resource-group securewave-rg

# Grant access to Key Vault
az keyvault set-policy \
  --name securewave-vault \
  --object-id YOUR_APP_PRINCIPAL_ID \
  --secret-permissions get list
```

---

## 8. SSL Certificate Setup (Production)

### Install Certbot

```bash
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx
```

### Obtain Certificate

```bash
# Stop nginx temporarily
sudo systemctl stop nginx

# Obtain certificate
sudo certbot certonly \
  --standalone \
  -d securewave.example.com \
  --email admin@securewave.com \
  --agree-tos

# Start nginx
sudo systemctl start nginx
```

### Configure Auto-Renewal

```bash
# Test renewal
sudo certbot renew --dry-run

# Certbot automatically sets up renewal via systemd timer
# Or manually add to crontab:
sudo crontab -e

# Add this line:
0 0,12 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'
```

---

## 9. Production Deployment

### Update Environment

```bash
ENVIRONMENT=production
USE_AZURE_KEY_VAULT=true
AZURE_KEY_VAULT_URL=https://your-vault.vault.azure.net/
DOMAIN=securewave.example.com
SSL_EMAIL=admin@securewave.com
```

### Deploy to Azure

```bash
# Build and deploy
./deploy.sh

# Or manually
zip -r deploy.zip . -x "*.git*" "venv/*" "*.pyc"
az webapp deployment source config-zip \
  --resource-group securewave-rg \
  --name securewave-app \
  --src deploy.zip
```

---

## 10. Monitoring & Health Checks

### Check Application Health

```bash
curl http://localhost:8000/api/health
```

### Check Database Connection

```bash
curl http://localhost:8000/api/ready
```

### Check Secrets Manager

```python
from services.secrets_manager import get_secrets_manager

manager = get_secrets_manager()
health = manager.health_check()
print(health)
```

### Check SSL Certificates

```python
from services.ssl_manager import get_ssl_manager

ssl = get_ssl_manager()
info = ssl.get_certificate_info()
print(info)
```

---

## 11. Common Issues & Solutions

### Email Not Sending

**Problem**: Verification emails not being received

**Solutions**:
1. Check SMTP credentials in `.env`
2. Enable "Less secure app access" for Gmail (or use App Password)
3. Check spam folder
4. Review logs: `tail -f app.log`
5. Test SMTP connection manually

### 2FA QR Code Not Loading

**Problem**: QR code image returns 404

**Solutions**:
1. Ensure pyotp is installed: `pip install pyotp`
2. Check that `/api/auth/2fa/qr` endpoint is accessible
3. Verify user has TOTP secret set up first

### Database Migration Fails

**Problem**: Alembic migration errors

**Solutions**:
1. Check database connection
2. Ensure PostgreSQL is running
3. Verify DATABASE_URL is correct
4. Run: `alembic downgrade -1` then `alembic upgrade head`

### Azure Key Vault Access Denied

**Problem**: Cannot retrieve secrets from Key Vault

**Solutions**:
1. Verify managed identity is enabled
2. Check Key Vault access policies
3. Ensure `AZURE_KEY_VAULT_URL` is correct
4. Test with Azure CLI: `az keyvault secret show --vault-name your-vault --name SECRET-NAME`

### SSL Certificate Renewal Fails

**Problem**: Let's Encrypt renewal fails

**Solutions**:
1. Check domain DNS is pointing to server
2. Ensure port 80 and 443 are open
3. Verify certbot is installed
4. Test: `sudo certbot renew --dry-run`

---

## 12. Testing Checklist

- [ ] User registration
- [ ] Email verification
- [ ] User login
- [ ] Password reset request
- [ ] Password reset confirmation
- [ ] 2FA setup
- [ ] 2FA verification
- [ ] Login with 2FA
- [ ] Backup code usage
- [ ] Account locking (5 failed attempts)
- [ ] Create subscription (Stripe)
- [ ] Create subscription (PayPal)
- [ ] View current subscription
- [ ] Upgrade subscription
- [ ] Cancel subscription
- [ ] View invoices
- [ ] Stripe webhook processing
- [ ] PayPal webhook processing

---

## Support

For issues or questions:
1. Check the logs: `tail -f app.log`
2. Review API docs: http://localhost:8000/api/docs
3. Check implementation summary: `AUTHENTICATION_AND_SECURITY_IMPLEMENTATION.md`

---

## Next Steps

After testing locally:
1. Deploy to staging environment
2. Configure production SMTP (SendGrid, Mailgun, etc.)
3. Set up Azure Key Vault
4. Obtain SSL certificates
5. Configure domain DNS
6. Set up monitoring and alerts
7. Perform security audit
8. Load testing

---

**Version**: 1.0.0
**Last Updated**: 2024-01-07
