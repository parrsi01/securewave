# Configuration and secrets

`.env.template` lists local backend settings. Create a private `.env` with
restricted permissions and fill it locally. Do not paste values into chat,
commit environment files or attach full service logs.

| Setting | Purpose |
| --- | --- |
| DATABASE_URL | Dedicated backend PostgreSQL connection |
| ENVIRONMENT | Development/testing/production behavior |
| ACCESS_TOKEN_SECRET / REFRESH_TOKEN_SECRET | Independent JWT signing secrets |
| AUTH_ENCRYPTION_KEY / WG_ENCRYPTION_KEY | Protected backend key material |
| WG_MOCK_MODE | Test-only peer behavior; false for real acceptance |
| SECUREWAVE_API_BASE_URL | Desktop HTTP base, normally https://api.securewaveapp.com/api |
| SECUREWAVE_TEST_DATABASE_URL | Disposable PostgreSQL test database only |

The template and validation code are normative for exact setting names. See
[`utils/env_validation.py`](../../utils/env_validation.py),
[`database/session.py`](../../database/session.py) and
[`services/jwt_service.py`](../../services/jwt_service.py).
Production must supply valid secrets; ephemeral development signing keys cause
old sessions to expire after restart. The native application stores its access
token and account-scoped WireGuard identity in the desktop secure store.

Root helper usage journals contain per-session reporting capabilities, not
account JWTs. They remain private under `/var/lib/securewave/usage`. Temporary
tunnel configuration contains local key material and must remain mode 0600.
Acceptance evidence retains public peer fields and counters, with no private
key or password. API hostnames and interface names can be documented publicly;
credentials and complete configurations cannot.
