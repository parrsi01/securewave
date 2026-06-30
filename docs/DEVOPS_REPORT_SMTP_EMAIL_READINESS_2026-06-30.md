# SMTP / Email Readiness Report - 2026-06-30

## Final status

SecureWave email verification and password reset are code-complete and covered
by backend tests, but not live-delivery-proven on this workstation. The local
environment has no configured SMTP/provider credentials and no transactional
app URL, so real outbound email delivery is externally blocked.

## What is proven

- Registration in non-demo mode creates an unverified account, sends a
  verification email through the configured email service, stores only a hashed
  verification token, and verifies the user with the raw emailed token.
- Verification tokens are single-use. Reused, invalid, expired, or structurally
  incomplete token records are rejected and cleaned up where applicable.
- Password reset requests are enumeration-safe at the API boundary and service
  layer.
- Password reset tokens are stored hashed, expire, are single-use, and clear the
  reset token state after successful password change or expiry.
- Transactional email configuration is environment-driven. SMTP, SendGrid, and
  SES provider readiness requires a configured `APP_URL` or `APP_BASE_URL` so
  verify/reset links cannot silently point to an example domain.
- Auth and email logs redact recipient/user email addresses and do not log raw
  verification or reset tokens.
- `scripts/release_preflight.sh` fails clearly when email provider variables,
  app URL, Fernet keys, or release tag are missing, and passes with a complete
  dummy SMTP-shaped release environment.

## Externally blocked

Real SMTP delivery was not attempted because the dotenv-loaded local email
configuration reported:

```text
provider=smtp
enabled=False
missing=SMTP_HOST,SMTP_PORT,SMTP_USER,SMTP_PASSWORD,FROM_EMAIL,APP_URL
app_url_configured=False
```

No fake SMTP success path was added. The remaining proof requires real provider
credentials and a recipient mailbox controlled by the release operator.

## Required env vars

For SMTP:

```bash
EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=smtp-user
SMTP_PASSWORD=...
FROM_EMAIL=noreply@securewave.app
FROM_NAME="SecureWave VPN"
APP_URL=https://securewave.app
AUTH_ENCRYPTION_KEY=<fernet-key>
WG_ENCRYPTION_KEY=<fernet-key>
DEMO_MODE=false
WG_MOCK_MODE=false
```

For SendGrid, use `EMAIL_PROVIDER=sendgrid`, `SENDGRID_API_KEY`, `FROM_EMAIL`,
`FROM_NAME`, and `APP_URL`. For SES, use `EMAIL_PROVIDER=ses`,
`AWS_SES_REGION`, `FROM_EMAIL`, `FROM_NAME`, and `APP_URL`.

## Automation

Use the ignored private env file path for release email settings:

```bash
bash scripts/email_release_gate.sh \
  --env-file securewave_private/release_email.env \
  --generate-missing-keys \
  --write-env-file \
  --dry-run-tag
```

After replacing the SMTP placeholders in
`securewave_private/release_email.env`, rerun:

```bash
bash scripts/email_release_gate.sh \
  --env-file securewave_private/release_email.env \
  --dry-run-tag
```

To run the live API proof after the provider is configured, use a controlled
mailbox and paste the received verification/reset links when prompted:

```bash
bash scripts/email_release_gate.sh \
  --env-file securewave_private/release_email.env \
  --dry-run-tag \
  --live-proof \
  --api-base https://api.securewaveapp.com/api \
  --email proof@example.com
```

The script automates the API calls and reset confirmation. It does not read the
inbox or create provider credentials; those remain external release operations.

## Validation performed

- `.venv/bin/python -m pytest tests/unit/test_email_config.py tests/unit/test_auth_email_flows.py tests/unit/test_env_validation.py tests/unit/test_release_preflight_email.py -q`
  - `52 passed`
- `.venv/bin/python -m pytest -q`
  - `336 passed`
- `python3 -m py_compile services/email_service.py services/enhanced_email_service.py services/auth_service.py routes/auth.py utils/env_validation.py models/email_log.py`
  - passed
- `git diff --check`
  - passed
- `env -i PATH="$PATH" HOME="$HOME" bash scripts/release_preflight.sh`
  - failed as expected with clear missing SMTP/app URL/key/tag errors
- Dummy complete SMTP-shaped release env:
  - `OK: Release preflight checks passed.`

## Remaining release risk

- Production SMTP/provider credentials must be provisioned outside the repo.
- A real deliverability proof should be run against a controlled mailbox before
  launch.
- Email reputation, SPF/DKIM/DMARC, bounce handling, and provider account
  limits remain operational/provider concerns and are not proven by local unit
  tests.
