# Native production deployment

SecureWave production remains a native Gunicorn service managed by
`securewave-api.service`. Verified `master` revisions are deployed into
`/opt/securewave-beta/releases/<git-sha>` and activated through the existing
`/opt/securewave-beta/current` symlink. The workflow refuses to deploy if that
contract is not already present.

The GitHub `production` environment requires these repository environment
variables:

- `SECUREWAVE_PRODUCTION_HOST`
- `SECUREWAVE_PRODUCTION_USER` (optional; defaults to `securewave`)
- `SECUREWAVE_PRODUCTION_RELEASE_ROOT` (optional; defaults to
  `/opt/securewave-beta`)
- `SECUREWAVE_PRODUCTION_SERVICE` (optional; defaults to
  `securewave-api.service`)
- `SECUREWAVE_PRODUCTION_LOCAL_URL` (optional; defaults to
  `http://127.0.0.1:8000`)

It also requires two environment secrets:

- `SECUREWAVE_PRODUCTION_SSH_KEY`: a deployment key authorized for the existing
  host and native release workflow.
- `SECUREWAVE_PRODUCTION_KNOWN_HOSTS`: the pinned SSH known-hosts entry for that
  host.

Do not put these values in repository files. The deployment workflow writes
them to temporary runner files, uses strict host-key verification, and removes
the runner after the job.

Every push to `master` runs path-aware CI. A successful CI run triggers
`.github/workflows/deploy-production.yml`, which deploys the exact verified Git
SHA with `scripts/deploy_native_production.sh`. The deployment records
`.release.json` and `.release.env`, applies existing Alembic migrations,
validates published download artifacts, atomically activates the release, and
verifies public health, readiness, downloads, version, and exact commit
identity. The native systemd unit reads `.release.env` through the `current`
symlink so each restart reports the activated release identity. A failed
activation restores the previous release pointer.

Client `.deb` publication remains explicit. A backend or website deployment
does not rebuild or silently replace client package bytes.
