# SecureWave Backend Deployment Guide (Hetzner)

## 1. Prepare environment
1. Copy `.env.example.backend` to `.env` and set real values.
2. Ensure `DEMO_MODE=false` and `WG_MOCK_MODE=false`.
3. Set `DATABASE_URL` to PostgreSQL.

## 2. Deploy backend
```bash
bash scripts/deploy_backend.sh
```

This runs:
- dependency install
- Alembic migrations
- env validation
- health/security smoke checks

## 3. Start service
```bash
bash scripts/run_backend.sh
```

## 4. Generate OpenAPI artifact
```bash
python scripts/generate_openapi.py
```

Output: `docs/openapi/securewave-openapi.json`
