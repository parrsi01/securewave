# SecureWave VPN - Enterprise VPN Platform

> Professional VPN service with AI-powered server optimization, military-grade encryption, and modern 2026 UI design.

## Demo Status
- ✅ Auth flow (register/login/logout) with immediate redirect to dashboard
- ✅ Demo VPN sessions (connect/disconnect/status/config) at website level
- ✅ Settings & subscription pages (demo UI)
- ✅ Mobile-first responsive UI (Safari iPhone)
- ✅ Azure deploy script for single-app FastAPI
- ✅ Frontend smoke checklist in `SMOKE_TEST.md`

## Azure Demo Deploy
- Use `deploy_securewave_single_app.sh` for a clean single-app deploy.
- See `AZURE_DEPLOY.md` for exact steps.

## What's Planned
- Native iOS/macOS clients using WireGuard
- Real VPN peer provisioning and server management
- Billing enforcement with Stripe webhooks

## Quick Start

### Option 1: Local Development
```bash
bash deploy.sh local
```
Access at: http://localhost:8000

### Option 2: Azure Production Deployment
```bash
bash deploy.sh azure
```
Your app will be live at: https://securewave-web.azurewebsites.net

### Option 3: Interactive Menu
```bash
bash deploy.sh
```
Choose from:
1. Local Development
2. Azure Production
3. Diagnostics
4. Exit

## Deployment Script Features

The new unified `deploy.sh` replaces all previous deployment scripts:
- ✅ **Local development** with auto-reload
- ✅ **Azure cloud deployment** with health checks
- ✅ **Diagnostics** and troubleshooting
- ✅ **Beautiful colored output**
- ✅ **Error handling** and validation
- ✅ **Progress tracking** at every step

## What Changed (2026-01-03 Update)

### 🎨 UI/UX Modernization
- ✅ Updated to Bootstrap 5.3.3 with 2026 design patterns
- ✅ Modern glassmorphism and neumorphism effects
- ✅ Smooth animations and transitions
- ✅ Gradient buttons with hover effects
- ✅ Modern typography (Inter + Space Grotesk fonts)
- ✅ Improved mobile responsiveness
- ✅ Better accessibility (WCAG 2.1 compliant)
- ✅ Performance optimizations (lazy loading, optimized fonts)

### 🚀 Deployment Consolidation
**Removed scripts:**
- ~~deploy_azure.sh~~
- ~~deploy_universal.sh~~
- ~~deploy_production.sh~~
- ~~diagnose_and_fix.sh~~
- ~~start_dev.sh~~
- ~~infrastructure/deploy_vpn_server.sh~~
- ~~infrastructure/health_check.sh~~

**New unified script:**
- ✅ `deploy.sh` - One script for everything

### 🧹 Project Cleanup
- ✅ Removed duplicate `frontend/` directory (now using `static/` only)
- ✅ Cleaned up 27+ redundant deployment ZIP files
- ✅ Removed old log files and temporary artifacts
- ✅ Removed empty `deployments/` directory
- ✅ Streamlined project structure

### 📊 New Documentation
- ✅ **CAPACITY_ANALYSIS.md** - Comprehensive capacity analysis
  - Current capabilities (50-75 concurrent users on B1 tier)
  - VPN capacity analysis (mock mode vs production)
  - Scaling roadmap (0 → 100K+ users)
  - Cost projections ($13/month → $5K+/month)
  - Performance bottlenecks and solutions
  - Compliance readiness (GDPR, SOC2, etc.)

## Architecture

```
SecureWave VPN
├── Backend (FastAPI + Python 3.12)
│   ├── AI-Powered Server Optimization (MARL + XGBoost)
│   ├── WireGuard VPN Integration
│   ├── Stripe + PayPal Payments
│   └── SQLite/PostgreSQL Database
├── Frontend (Bootstrap 5.3.3 + Modern JS)
│   ├── Glassmorphism UI
│   ├── Responsive Design
│   └── 2026 Design Patterns
└── Infrastructure
    ├── Azure App Service (B1+)
    ├── Gunicorn + Uvicorn Workers
    └── Automated Deployment
```

## Current Capabilities

### ✅ What Works Right Now
- **Dashboard Access:** 50-75 concurrent users (B1 tier)
- **User Registration:** Unlimited with email/password
- **Payment Processing:** Stripe & PayPal integration
- **VPN Config Generation:** Unlimited (QR codes included)
- **Server Optimizer:** AI-powered server selection
- **Mock VPN Mode:** Demo VPN functionality
- **API Documentation:** Interactive Swagger UI
- **Rate Limiting:** 200 requests/minute per IP
- **Security:** JWT auth, CORS protection, SQL injection prevention

### ⚠️ Current Limitations
- **VPN Connections:** Mock mode only (no actual VPN servers yet)
- **Concurrency:** Limited to 50-75 concurrent users on B1 tier
- **Database:** SQLite (upgrade to PostgreSQL recommended at 5K+ users)
- **Single Server:** No redundancy (single point of failure)

### 🚀 Easy Upgrades Available
- **More Users:** Upgrade to B2 ($70/month) → 150-200 concurrent users
- **Better Performance:** Upgrade to S1 ($100/month) → 200-300 users
- **PostgreSQL:** Add Azure Database for better write performance
- **Real VPN Servers:** Deploy WireGuard containers to Azure
- **Multi-Region:** Deploy to multiple Azure regions for global availability

## Capacity Summary

| Tier | Cost/Month | Concurrent Users | Best For |
|------|------------|------------------|----------|
| B1 (Current) | $13 | 50-75 | MVP, Small Teams, Demo |
| B2 | $70 | 150-200 | Startups < 1K users |
| S1 | $100 | 200-300 | Growing Companies |
| P1V2 | $300 | 500-1,000 | Mid-Market |
| P3V3+ | $2,000+ | 5,000+ | Enterprise |

**See CAPACITY_ANALYSIS.md for detailed analysis and scaling roadmap.**

## File Structure

```
securewave/
├── deploy.sh              # 🆕 Unified deployment script
├── startup.sh             # Azure App Service startup
├── main.py                # FastAPI application entry
├── requirements.txt       # Python dependencies
├── database/              # Database models & session
├── models/                # SQLAlchemy ORM models
├── routers/               # API route handlers
├── services/              # Business logic services
├── infrastructure/        # VPN server management
├── static/                # Frontend files (HTML/CSS/JS)
│   ├── home.html         # 🎨 Modernized 2026 design
│   ├── login.html
│   ├── dashboard.html
│   └── css/
│       └── professional.css
├── CAPACITY_ANALYSIS.md   # 📊 Capacity & capability report
└── README.md              # This file
```

## Technology Stack

### Backend
- **FastAPI** - Modern Python web framework
- **SQLAlchemy** - ORM for database operations
- **Pydantic** - Data validation
- **Gunicorn + Uvicorn** - Production ASGI server
- **Stripe & PayPal** - Payment processing

### Frontend
- **Bootstrap 5.3.3** - Latest stable CSS framework
- **Modern JavaScript** - ES6+ features
- **Inter & Space Grotesk** - Modern typography
- **Bootstrap Icons** - Icon library
- **Glassmorphism** - 2026 design trend

### AI/ML
- **MARL** - Multi-Agent Reinforcement Learning
- **XGBoost** - Gradient boosting for optimization
- **NumPy & Pandas** - Data processing

### VPN
- **WireGuard** - Modern VPN protocol
- **ChaCha20** - Military-grade encryption

### Infrastructure
- **Azure App Service** - Managed web hosting
- **Azure Database** - PostgreSQL (optional)
- **Azure CDN** - Content delivery (optional)
- **Docker** - Containerization support

## API Endpoints

### Public Endpoints
- `GET /` - Home page (redirects to /home.html)
- `GET /api/health` - Health check
- `GET /api/ready` - Readiness check
- `GET /api/docs` - Interactive API documentation

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/refresh` - Refresh access token
- `POST /api/auth/logout` - User logout

### VPN Management
- `GET /api/vpn/servers` - List available VPN servers
- `POST /api/vpn/config` - Generate VPN configuration
- `GET /api/vpn/connections` - List user connections

### Payments
- `POST /api/payment/stripe/create-checkout` - Stripe checkout
- `POST /api/payment/paypal/create-order` - PayPal order
- `GET /api/payment/subscription` - Get subscription status

### Server Optimizer (AI)
- `GET /api/optimizer/recommend` - Get optimal server recommendation
- `GET /api/optimizer/servers` - List all servers with health metrics

## Environment Variables

```bash
# Application
ENVIRONMENT=production
PORT=8000

# Database
DATABASE_URL=sqlite:///./securewave.db

# Security
ACCESS_TOKEN_SECRET=<generated-automatically>
REFRESH_TOKEN_SECRET=<generated-automatically>
CORS_ORIGINS=https://your-domain.com

# VPN Configuration
WG_MOCK_MODE=true
WG_DATA_DIR=/tmp/wg_data

# Payments (Optional)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
PAYPAL_CLIENT_ID=...
PAYPAL_CLIENT_SECRET=...
```

## Testing

### Run Local Tests
```bash
# Install dev dependencies
pip install -r requirements_dev.txt

# Run tests
pytest

# Run with coverage
pytest --cov=. --cov-report=html
```

### Test Azure Deployment
```bash
# Deploy to Azure
bash deploy.sh azure

# Run diagnostics
bash deploy.sh diagnostics

# Check health
curl https://securewave-web.azurewebsites.net/api/health

# View logs
az webapp log tail -g SecureWaveRG -n securewave-web
```

## Monitoring & Logging

### View Logs
```bash
# Tail live logs
az webapp log tail -g SecureWaveRG -n securewave-web

# Download logs
az webapp log download -g SecureWaveRG -n securewave-web --log-file logs.zip

# View specific log file
az webapp log show -g SecureWaveRG -n securewave-web
```

### Health Checks
- **Health:** https://securewave-web.azurewebsites.net/api/health
- **Ready:** https://securewave-web.azurewebsites.net/api/ready
- **API Docs:** https://securewave-web.azurewebsites.net/api/docs

### Recommended Monitoring Tools
- **UptimeRobot** - Free uptime monitoring
- **Azure Application Insights** - Performance monitoring
- **Sentry** - Error tracking
- **Datadog/New Relic** - Full APM stack

## Scaling Guide

### When to Upgrade?

**Upgrade to B2 ($70/month) when:**
- Consistently >50 concurrent users
- Response times >500ms
- CPU usage >80%

**Upgrade to PostgreSQL when:**
- Database write errors
- >5,000 registered users
- Need for high availability

**Add Redis when:**
- Session management issues
- >100 concurrent users
- Need for caching layer

**Go Multi-Region when:**
- Global user base
- Need for <100ms latency worldwide
- Enterprise SLA requirements (99.99%+)

## Security Best Practices

✅ **Implemented:**
- HTTPS/TLS 1.3 for all traffic
- JWT-based authentication
- Rate limiting (200 req/min)
- CORS protection
- SQL injection prevention (ORM)
- XSS protection headers
- Password hashing (bcrypt)

⚠️ **Recommended Additions:**
- WAF (Web Application Firewall)
- DDoS protection (Cloudflare/Azure)
- Security headers (HSTS, CSP)
- Regular dependency updates
- Penetration testing
- SOC 2 compliance audit

## Support & Documentation

- **Capacity Analysis:** See `CAPACITY_ANALYSIS.md`
- **API Documentation:** https://securewave-web.azurewebsites.net/api/docs
- **Deployment Guide:** This README
- **Issues:** Report bugs via GitHub Issues

## License

Proprietary - All Rights Reserved

---

**Built with ❤️ using FastAPI, WireGuard, and Bootstrap 5.3**
**Last Updated:** January 3, 2026
**Version:** 2.0.0
