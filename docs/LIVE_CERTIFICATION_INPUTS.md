# Linux WireGuard Live-Certification Inputs

These inputs are operator-owned. Repository scripts must not invent them,
register a disposable live account, or infer production when staging is absent.

## Stable account file

The ignored local path is:

```text
securewave_private/live_certification_account.env
```

Edit this file; do not execute it as a command. It must contain exactly one
existing stable staging account using these keys:

```dotenv
SECUREWAVE_RUNTIME_PROBE_EMAIL=
SECUREWAVE_RUNTIME_PROBE_PASSWORD=
```

The file must be a regular file owned by the current user with mode `0600`.
The containing `securewave_private` directory is ignored by Git and should use
mode `0700`. Do not paste either value into a command line, commit, diagnostic
bundle, issue, or chat.

## Explicit authorized staging API

Obtain the HTTPS API base from the staging operator. The repository does not
contain an authorized staging hostname and must not guess one from production.
Load it into only the current protected shell session:

```bash
read -r -p 'Authorized staging API URL: ' SECUREWAVE_API_BASE_URL
export SECUREWAVE_API_BASE_URL
export SECUREWAVE_CERT_AUTH_FILE="$PWD/securewave_private/live_certification_account.env"
```

Validate syntax, ownership, permissions, and credential presence without any
network request or secret output:

```bash
python3 scripts/check_live_certification_inputs.py
```

Only after that command passes may the WireGuard-only smoke or tunnel proof run:

```bash
python3 scripts/live_flutter_runtime_smoke.py --profile-repeats 2
python3 scripts/linux_app_vpn_tunnel_proof.py \
  --protocol wireguard --hold-seconds 60 --json
```

Production remains fail-closed unless the repository's separate explicit
production authorization option is deliberately supplied by an authorized
operator.

## Disposable PostgreSQL concurrency

PostgreSQL concurrency does not require a staging secret. With Docker and the
pinned Python environment available, run:

```bash
PYTHON_BIN=/path/to/pinned/.venv/bin/python \
  bash scripts/run_local_postgres_concurrency.sh
```

The runner starts the same digest-pinned PostgreSQL 15 image used by CI on a
random loopback port, applies Alembic, runs the focused concurrency tests, and
removes its container. It never connects to staging or production.
