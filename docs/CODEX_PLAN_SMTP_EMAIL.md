# Codex Plan — Finish SMTP / Email (T7, the real feature gap)

**Branch:** `master` (backend truth). **Priority:** in-scope for live-product
readiness after P0/P1 real-tunnel blockers are safe. Register can still return a
token directly, but real users need verification and reset to work; this is the
feature gap `TODO.md` flags and it surfaces as "Email unverified" on the Account
tab plus a dead reset flow.

## Current state (verified)
- `services/email_service.py` already speaks SMTP (reads `SMTP_HOST/PORT/USER/
  PASSWORD/FROM_*`, `EMAIL_PROVIDER` default `smtp`) and exposes
  `config_status()` + `_provider_ready()`. `requirements.txt` also pins
  `sendgrid` and `boto3`, so providers smtp / sendgrid / ses are intended.
- `main.py` exposes `/api/health/email` (returns 503 when not configured) and
  CSRF-exempts `/api/auth/register`, `/api/auth/password-reset/request`,
  `/api/auth/password-reset/confirm`.
- When unconfigured the service degrades gracefully (disabled) — preserve that.

## Tasks
1. **Pick + wire a provider.** Choose SMTP (simplest: an app-password mailbox) or
   SendGrid/SES. Put creds in env only (`.env` locally, Hetzner secret store in
   prod); update `.env.template` and `.env.production.example` with placeholders.
   Never commit real creds (README public-repo rules).
2. **Verify health.** `GET /api/health/email` must return `{"status":"ok"}` once
   configured. `scripts/demo_preflight.sh --live-go-no-go` treats this as a
   blocking release check; the default preflight reports it visibly without
   blocking local smoke runs.
3. **Verification email flow.** Confirm `routes/auth.py` register path generates a
   verification token and actually sends it via `EmailService`; implement/confirm
   the verify-token endpoint that flips `email_verified=true`. The Flutter
   Account tab already renders `Email verified / unverified` from `/auth/me`.
4. **Password-reset flow.** `/api/auth/password-reset/request` sends a tokenized
   reset link; `/api/auth/password-reset/confirm` consumes it and rotates the
   password. Confirm token expiry + single-use.
5. **Templates.** Use `jinja2` (already a dep) for verify + reset email bodies;
   keep them plaintext-safe and brand-correct.
6. **Tests.** Add `pytest` coverage with the SMTP layer mocked (e.g. monkeypatch
   `smtplib.SMTP`): assert a verify email is dispatched on register and a reset
   email on request, token round-trips, and unconfigured mode stays disabled (no
   crash). Optionally document a MailHog/`aiosmtpd` local capture for manual e2e.
7. **Redaction.** Ensure recipient addresses stay redacted in logs (the
   `RedactFilter` in `main.py` already scrubs emails — verify new log lines pass).

## Acceptance
- `/api/health/email` → ok with creds set; 503 without (unchanged).
- Register against a test inbox delivers a verify email; verifying flips the
  Account tab to "Email verified".
- Reset request delivers a reset email; confirm rotates the password; expired/
  reused tokens are rejected.
- `pytest` green; unconfigured machines still boot and run the demo unaffected.
- No secrets committed; `.env.template` documents every new var.

## Scope guard
If time-boxed, ship **verification only** and defer reset with an explicit
go-live exception. Do not hide the gap behind Presentation Mode or a staged demo
path.
