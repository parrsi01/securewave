# Backend API test matrix

Run these commands from the repository root. They are local-only and use mock
WireGuard mode; they do not deploy, contact SMTP/providers, or run load tests.

| Goal | Command |
| --- | --- |
| Fresh/legacy Alembic schema, drift check + API boundary | `TESTING=true AUTO_CREATE_TABLES=false .venv/bin/python -m pytest tests/integration/test_migrations.py -q` |
| Auth, profiles, devices, downloads, metering | `TESTING=true DEMO_MODE=true WG_MOCK_MODE=true AUTO_CREATE_TABLES=false .venv/bin/python -m pytest tests/integration/test_auth_hardening.py tests/integration/test_vpn_profile.py tests/integration/test_usage_metering.py tests/unit/test_downloads_manifest.py -q` |
| PostgreSQL migration and concurrency lane | `SECUREWAVE_TEST_POSTGRES_URL=postgresql://... TESTING=true AUTO_CREATE_TABLES=false .venv/bin/python -m pytest tests/integration/test_postgres_usage_concurrency.py -q` |
| Full backend suite | `SKIP_INSTALL=true PYTEST_ARGS="tests -v" bash scripts/run_backend_tests.sh` |
| Lint, compile, and whitespace checks | `.venv/bin/python -m ruff check --select E9,F63,F7,F82 main.py database models routes routers services utils alembic tests && .venv/bin/python -m compileall -q main.py database models routes routers services utils alembic tests && git diff --check` |

`0006_backend_api_schema` is an adaptive, online reconciliation migration for
legacy database histories. Run `alembic upgrade head` directly against the
target database; `alembic upgrade head --sql` is intentionally rejected at
that revision because an offline script cannot safely inspect divergent legacy
table/column state.

The PostgreSQL lane is optional locally and skipped without
`SECUREWAVE_TEST_POSTGRES_URL`; CI supplies it after applying Alembic to a
fresh PostgreSQL schema.
