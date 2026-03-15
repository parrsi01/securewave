# SecureWave Backend Deployment Guide (Hetzner)

## 1. Prepare environment
1. Create `/etc/securewave/env` on the VPS from your production secrets.
2. Ensure `ENVIRONMENT=production` and `TESTING=false`.
3. Set `DATABASE_URL` to PostgreSQL and keep SQLite only as an explicit fallback with `ALLOW_SQLITE_PRODUCTION=true`.
4. Set real SMTP and Stripe variables before deployment.

## 2. Deploy backend
```bash
VPS_HOST=<server-ip> VPS_USER=securewave bash scripts/ops/hetzner_deploy.sh
```

This runs:
- dependency install
- Alembic migrations
- systemd unit install for `securewave-api`
- health smoke checks against `127.0.0.1:8080/api/health`

If you are promoting an existing SQLite-backed node to PostgreSQL first:
```bash
python scripts/ops/migrate_sqlite_to_postgres.py \
  --source-url sqlite:////tmp/securewave.db \
  --target-url postgresql+psycopg2://securewave:<password>@127.0.0.1:5432/securewave \
  --run-migrations \
  --truncate
```

## 3. Start and verify service
```bash
ssh securewave@<server-ip> 'sudo systemctl status securewave-api --no-pager'
ssh securewave@<server-ip> 'curl -fsS http://127.0.0.1:8080/api/health'
```

## 4. Configure nginx + TLS
```bash
ssh root@<server-ip> 'bash -s' < scripts/hetzner_bootstrap.sh
ssh root@<server-ip> \
  "bash /opt/securewave/scripts/setup_tls_certbot.sh --domain securewave.app --domain www.securewave.app --email ops@securewave.app"
```

## 5. Generate OpenAPI artifact
```bash
python scripts/generate_openapi.py
```

Output: `docs/openapi/securewave-openapi.json`
