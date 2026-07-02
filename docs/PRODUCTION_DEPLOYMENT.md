# Production Deployment

SecureWave now has a container release workflow:

```bash
gh workflow run container-release.yml
```

Tagged releases also publish backend images to:

```text
ghcr.io/parrsi01/securewave:<tag>
ghcr.io/parrsi01/securewave:sha-<commit>
```

Use the deploy script only after the Hetzner host has been provisioned and
hardened. The script uploads `deploy/hetzner/compose.yaml` to the remote app
directory as `compose.yaml`; the host must already have a private `.env` file
with production secrets.

```bash
export SECUREWAVE_PRODUCTION_HOST="<host-or-ip>"
export SECUREWAVE_PRODUCTION_USER="securewave"
export SECUREWAVE_REMOTE_APP_DIR="/opt/securewave"
export SECUREWAVE_PRODUCTION_IMAGE="ghcr.io/parrsi01/securewave:<tag-or-sha>"
export CONFIRM_DEPLOY="securewave-production"

bash scripts/deploy_production.sh
```

This pass adds the production delivery path, but it does not execute a live
production deploy because the current workspace does not provide the target
host, registry image tag, SSH route, or production environment secrets.
