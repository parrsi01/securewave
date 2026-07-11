# Backend API refactor validation summary

Date: 2026-07-11

## Safety scope

- No production deployment was performed.
- No external load test was run.
- No SMTP or provider integration action was run.
- Evidence is local, redacted, and does not contain credentials, private keys,
  bearer tokens, or traffic destinations.

## Commands and outcomes

| Check | Result |
| --- | --- |
| Fresh isolated SQLite Alembic upgrade + repeat + drift check | Passed: `0006_backend_api_schema (head)` and `No new upgrade operations detected` |
| Fresh isolated PostgreSQL 16 upgrade + repeat + drift check | Passed: `0006_backend_api_schema (head)` and `No new upgrade operations detected` |
| Fresh schema vs ORM table/column presence | Passed: 25 tables; no missing mapped tables or columns |
| PostgreSQL pristine historical DDL ordering through `0005` | Passed: `vpn_servers` exists before `wireguard_peers` foreign keys are applied |
| Legacy `0004` plus pre-created current audit table -> head | Passed in `tests/integration/test_migrations.py` |
| Legacy nullable subscription timestamp -> head | Passed: value backfilled and `subscriptions.created_at` made non-null |
| Migration-created isolated API boundary | Passed in `tests/integration/test_migrations.py` |
| Documented focused API/security suite | Passed: 44 tests; 2 SQLite expression-index reflection warnings documented below |
| Full backend pytest suite | Passed: 332 tests; the PostgreSQL-only concurrency lane is skipped when its URL is absent |
| PostgreSQL concurrent metering lane | Passed separately: 1 test with `SECUREWAVE_TEST_POSTGRES_URL` against the isolated PostgreSQL 16 container |
| Ruff lint (`E9,F63,F7,F82`) | Passed across backend, migrations, tests, initializer, and inventory generator |
| Python compile check | Passed: `compileall` across backend, migrations, tests, and initializer |
| High-severity Bandit scan | Passed with no high-severity findings; Bandit emitted existing comment-parser warnings only |
| Whitespace/conflict check | Passed: `git diff --check` |

SQLite/SQLAlchemy cannot reflect expression-based indexes for comparison, so
the SQLite drift check emits warnings for `uq_users_email_lower` and
`uq_wireguard_peer_user_device_name`. The indexes are asserted directly and
were also reflected successfully from PostgreSQL. The PostgreSQL test container
used synthetic local credentials and had no production connection.

## Evidence limits

These checks prove local source behavior and isolated database/API boundaries.
They do not prove production deployment status, provider readiness, data-plane
reachability, live tunnel capacity, or release readiness.
