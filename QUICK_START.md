# SecureWave VPN - Quick Start Guide

## 🚀 Get Running in 60 Seconds

### Local Development
```bash
cd /path/to/securewave
bash deploy.sh local
```
✅ **Done!** Visit http://localhost:8000

### Azure Production
```bash
bash deploy.sh azure
```
✅ **Done!** Visit https://securewave-web.azurewebsites.net

---

## 📋 Prerequisites

### Local Development
- ✅ Python 3.12+
- ✅ pip (Python package manager)
- ✅ 2GB free RAM
- ✅ 500MB free disk space

### Azure Deployment
- ✅ Azure CLI installed ([Download](https://aka.ms/installazurecli))
- ✅ Azure account (free tier works!)
- ✅ Logged in: `az login`

---

## 🎯 Common Tasks

### Start Local Server
```bash
bash deploy.sh local
```

### Deploy to Azure
```bash
bash deploy.sh azure
```

### Check Azure Health
```bash
bash deploy.sh diagnostics
```

### View Azure Logs
```bash
az webapp log tail -g SecureWaveRG -n securewave-web
```

### Restart Azure App
```bash
az webapp restart -g SecureWaveRG -n securewave-web
```

### Stop Azure App (save costs)
```bash
az webapp stop -g SecureWaveRG -n securewave-web
```

### Delete Everything (cleanup)
```bash
az group delete -n SecureWaveRG -y
```

---

## 🔧 Configuration

### Environment Variables

Create `.env` file (local only):
```bash
# Application
ENVIRONMENT=development
PORT=8000

# Database
DATABASE_URL=sqlite:///./securewave.db

# Security (auto-generated in Azure)
ACCESS_TOKEN_SECRET=your-secret-here
REFRESH_TOKEN_SECRET=your-secret-here

# VPN
WG_MOCK_MODE=true
WG_DATA_DIR=./wg_data

# Optional: Payments
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
```

**Note:** Azure deployment auto-generates secrets!

---

## 🌐 Access Points

### Local Development
- 🏠 Home: http://localhost:8000/home.html
- 🔐 Login: http://localhost:8000/login.html
- 📊 Dashboard: http://localhost:8000/dashboard.html
- 📚 API Docs: http://localhost:8000/api/docs
- ❤️ Health: http://localhost:8000/api/health

### Azure Production
- 🏠 Home: https://securewave-web.azurewebsites.net/home.html
- 🔐 Login: https://securewave-web.azurewebsites.net/login.html
- 📊 Dashboard: https://securewave-web.azurewebsites.net/dashboard.html
- 📚 API Docs: https://securewave-web.azurewebsites.net/api/docs
- ❤️ Health: https://securewave-web.azurewebsites.net/api/health

---

## 🐛 Troubleshooting

### Local Issues

**Problem:** `bash: deploy.sh: Permission denied`
```bash
chmod +x deploy.sh
bash deploy.sh local
```

**Problem:** `python3: command not found`
```bash
# macOS
brew install python@3.12

# Ubuntu/Debian
sudo apt install python3.12

# Windows
# Download from python.org
```

**Problem:** Port 8000 already in use
```bash
# Find and kill process using port 8000
lsof -ti:8000 | xargs kill -9

# Or use different port
PORT=8080 bash deploy.sh local
```

**Problem:** Database errors
```bash
# Reset database
rm securewave.db
bash deploy.sh local
```

### Azure Issues

**Problem:** `az: command not found`
```bash
# Install Azure CLI
# macOS
brew install azure-cli

# Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows
# Download from aka.ms/installazurecli
```

**Problem:** Not logged in to Azure
```bash
az login
# Follow browser prompts
```

**Problem:** Deployment fails
```bash
# Run diagnostics
bash deploy.sh diagnostics

# View logs
az webapp log tail -g SecureWaveRG -n securewave-web

# Restart app
az webapp restart -g SecureWaveRG -n securewave-web
```

**Problem:** App not responding after deployment
```bash
# Wait 2-3 minutes for cold start
# Then check health
curl https://securewave-web.azurewebsites.net/api/health

# If still not working, check logs
az webapp log tail -g SecureWaveRG -n securewave-web
```

**Problem:** Want to change app name
```bash
# Edit deploy.sh
# Change: APP_NAME="securewave-web"
# To: APP_NAME="your-name-here"

# Then deploy
bash deploy.sh azure
```

---

## 📊 Monitoring

### Check Application Health
```bash
# Local
curl http://localhost:8000/api/health

# Azure
curl https://securewave-web.azurewebsites.net/api/health
```

### View Real-time Logs
```bash
az webapp log tail -g SecureWaveRG -n securewave-web
```

### Download All Logs
```bash
az webapp log download -g SecureWaveRG -n securewave-web --log-file logs.zip
unzip logs.zip
```

### Check Resource Usage
```bash
# CPU and Memory
az webapp show -g SecureWaveRG -n securewave-web --query "state,availabilityState"

# Check app service plan
az appservice plan show -g SecureWaveRG -n SecureWavePlan
```

---

## 💰 Cost Management

### Current Costs (Azure B1)
- **Monthly:** ~$13/month
- **Daily:** ~$0.43/day
- **Hourly:** ~$0.018/hour

### Save Money

**Stop app when not in use:**
```bash
# Stop (saves ~70% of costs)
az webapp stop -g SecureWaveRG -n securewave-web

# Start when needed
az webapp start -g SecureWaveRG -n securewave-web
```

**Delete everything when done:**
```bash
az group delete -n SecureWaveRG -y
```

**Free alternatives for testing:**
- Azure Free Tier: First month free
- Local development: Always free

---

## 🔐 Security Checklist

### Before Production Launch

- [ ] Change default secrets in Azure app settings
- [ ] Enable HTTPS only (already configured)
- [ ] Set up custom domain (optional)
- [ ] Configure SSL certificate (automatic with Azure)
- [ ] Enable Application Insights (monitoring)
- [ ] Set up automated backups
- [ ] Configure rate limiting (already set: 200 req/min)
- [ ] Review CORS settings
- [ ] Enable firewall rules (if needed)
- [ ] Set up alerts for errors/downtime

---

## 🚀 Performance Tips

### Improve Response Time
1. Upgrade from B1 to B2 (2x faster: $70/month)
2. Add Redis for caching
3. Enable CDN for static files
4. Migrate to PostgreSQL for better concurrency

### Handle More Users
- B1: 50-75 users → Upgrade to B2
- B2: 150-200 users → Upgrade to S1
- S1: 200-300 users → Upgrade to P1V2

See `CAPACITY_ANALYSIS.md` for detailed scaling guide.

---

## 📚 Learn More

- **Full Documentation:** `README.md`
- **Capacity Analysis:** `CAPACITY_ANALYSIS.md`
- **API Documentation:** `/api/docs` (when running)
- **Azure Docs:** https://docs.microsoft.com/azure

---

## 🆘 Getting Help

1. **Check logs first:**
   ```bash
   bash deploy.sh diagnostics
   ```

2. **View detailed logs:**
   ```bash
   az webapp log tail -g SecureWaveRG -n securewave-web
   ```

3. **Common fixes:**
   - Restart app: `az webapp restart -g SecureWaveRG -n securewave-web`
   - Redeploy: `bash deploy.sh azure`
   - Reset: Delete and redeploy

4. **Still stuck?**
   - Check `README.md` for detailed docs
   - Review `CAPACITY_ANALYSIS.md` for architecture info
   - Check Azure portal for errors

---

## ✅ Success Checklist

After deployment, verify:

- [ ] Health endpoint works: `/api/health`
- [ ] Home page loads: `/home.html`
- [ ] Login page works: `/login.html`
- [ ] API docs accessible: `/api/docs`
- [ ] Can register new user
- [ ] Can login with user
- [ ] Dashboard accessible after login
- [ ] VPN config generation works
- [ ] Logout works properly

---

**Last Updated:** January 3, 2026
**Version:** 2.0.0

**🎉 You're all set! Start building amazing VPN experiences!**
