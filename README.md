# SecureWave Linux Beta 1

SecureWave is a small, portable Linux VPN beta:

`website -> one ARM64 .deb -> Flutter Linux app -> FastAPI -> PostgreSQL + one Hetzner WireGuard target`

The real build uses email/password authentication, one bearer access token, one WireGuard profile, and a native Linux helper installed by the Debian package. The app has only `CONNECT` and `DISCONNECT`; status, health, and local traffic counters are visible without becoming another control plane.

Demo mode is separate and deterministic. Run it with `--dart-define=SECUREWAVE_DEMO_MODE=true`; it never contacts the backend and never calls the native helper.

Beta 1 supports Ubuntu 24.04 LTS on ARM64 only. amd64 and other distributions remain future work until they have the same package, clean-install, and live WireGuard evidence.

## Local workflow

```bash
./scripts/run_linux_beta.sh backend
./scripts/run_linux_beta.sh flutter
./scripts/test_linux_beta.sh
./scripts/build_linux_deb.sh
./scripts/verify_linux_deb.sh securewave_app/build/packaging/securewave-vpn_<version>_<arch>.deb
```

The backend expects PostgreSQL for real deployment. Apply the preserved Alembic history with `alembic upgrade head`; historical migrations are not rewritten even though retired product tables are no longer part of the active ORM.

The real Flutter build has no localhost fallback. Set `SECUREWAVE_API_BASE_URL` to the intended HTTPS API when building a release package; the builder rejects empty, localhost, and placeholder URLs.

## Boundaries

- One production branch and one deterministic demo branch are the only product branches planned after review; historical refs are retained.
- The package declares its GTK, secure-storage, EGL/GLES, WireGuard, iproute2, iptables, and systemd runtime dependencies and contains the contract-13 helper. It has no retired VPN or payment dependencies.
- No email delivery, email verification, billing, subscriptions, region picker, server picker, protocol picker, or optimizer is on the Beta 1 runtime path.
- Do not deploy, publish, push, or merge from local certification commands.

See [`docs/BETA_ACCEPTANCE_REPORT.md`](docs/BETA_ACCEPTANCE_REPORT.md), [`docs/BETA_SIMPLIFICATION_PLAN.md`](docs/BETA_SIMPLIFICATION_PLAN.md), [`docs/LINUX_BETA.md`](docs/LINUX_BETA.md), and [`docs/HETZNER_RUNBOOK.md`](docs/HETZNER_RUNBOOK.md).
