# SecureWave TODO

## Linux VM Hetzner Backend Handoff - 2026-07-02

Objective: continue the backend infrastructure verification from the Linux VM, because Hetzner credentials, Terraform state, live account material, or deployment environment files may exist there rather than on this macOS checkout.

### Preconditions

- Open and start the Linux VM before continuing.
- Confirm whether the VM is reachable from macOS:
  - `ssh securewave-linux`
  - If SSH still times out, continue inside the VM terminal directly.
- Do not print secret values to the terminal, logs, screenshots, or artifacts. Only record whether required variables/files are present.
- Work from the Linux branch first, because the latest Hetzner backend fixes were pushed there:
  - `git fetch origin`
  - `git switch Linux`
  - `git pull --ff-only origin Linux`

### Discover VM Backend Material

Run these checks inside the Linux VM and save non-secret output under `artifacts/linux-vm-hetzner-scan/`.

```bash
uname -a
command -v git
command -v docker
command -v terraform
command -v python3

find "$HOME" -maxdepth 4 -type f \
  \( -name 'terraform.tfstate' \
  -o -name 'terraform.tfvars' \
  -o -name '*.tfvars' \
  -o -name 'release_email.env' \
  -o -name 'billing_release.env' \
  -o -name 'live_certification_account.env' \
  -o -name '.env' \) \
  -print

for name in \
  HETZNER_API_TOKEN \
  TF_VAR_hcloud_token \
  SECUREWAVE_PRODUCTION_HOST \
  SECUREWAVE_PRODUCTION_IMAGE \
  SECUREWAVE_CERT_AUTH_FILE \
  SECUREWAVE_LIVE_ACCOUNT_FILE
do
  if [ -n "${!name:-}" ]; then
    printf '%s=set\n' "$name"
  else
    printf '%s=unset\n' "$name"
  fi
done
```

### Validate Hetzner Infrastructure

Run from the repo root after switching to `Linux`.

```bash
terraform -chdir=infrastructure/hetzner fmt -check
terraform -chdir=infrastructure/hetzner init
terraform -chdir=infrastructure/hetzner validate
TF_DIR=infrastructure/hetzner bash scripts/check_cost_guardrails.sh infrastructure/hetzner/terraform.tfvars
test -f deploy/hetzner/compose.yaml
bash -n scripts/deploy_production.sh scripts/hetzner_bootstrap.sh scripts/check_cost_guardrails.sh
```

If `HETZNER_API_TOKEN` or `TF_VAR_hcloud_token` is available, run a read-only fleet audit and store the output as evidence:

```bash
mkdir -p artifacts/linux-vm-hetzner-scan
python3 infrastructure/hetzner/audit_vpn_fleet.py \
  --json-out artifacts/linux-vm-hetzner-scan/hetzner_fleet_audit.json
```

### Validate Live Backend Surface

Run these only against SecureWave-owned production hosts.

```bash
curl -fsS https://api.securewaveapp.com/api/health
curl -fsS https://api.securewaveapp.com/api/downloads
```

If live certification account credentials exist, run the live gate without exposing credentials:

```bash
bash scripts/demo_preflight.sh --live-go-no-go --skip-build
```

If a connected Linux VPN client is available, run the final connected gate:

```bash
bash scripts/final_linux_demo_gate.sh --connected
```

### Production Deploy Readiness

Only deploy after all of the following are true:

- The Hetzner Terraform validation passes.
- Docker is installed and running on the target host.
- `deploy/hetzner/compose.yaml` exists on the branch being deployed.
- The production host has a real `.env` file in the expected deployment directory.
- `SECUREWAVE_PRODUCTION_HOST` and `SECUREWAVE_PRODUCTION_IMAGE` are set.
- The deployment image tag is immutable and traceable to a reviewed commit.

Deploy command, when authorized:

```bash
CONFIRM_DEPLOY=securewave-production \
SECUREWAVE_PRODUCTION_HOST="$SECUREWAVE_PRODUCTION_HOST" \
SECUREWAVE_PRODUCTION_IMAGE="$SECUREWAVE_PRODUCTION_IMAGE" \
bash scripts/deploy_production.sh
```

### Evidence To Capture

- `git rev-parse HEAD`
- Terraform fmt/init/validate output
- Cost guardrail output
- Docker and Terraform versions
- Read-only Hetzner fleet audit JSON, if credentials are present
- Health endpoint output
- Downloads endpoint output
- Demo/live gate output, if credentials are present

Do not mark this task complete without evidence artifacts. Do not commit or upload secrets.

### Blockers To Escalate

- Linux VM cannot be opened or reached.
- Terraform is not installed and cannot be installed safely.
- Docker is unavailable on the deployment target.
- No Hetzner API token, Terraform state, or tfvars can be found.
- Production host `.env` is missing.
- Live account credentials are missing.
- Production health checks fail.

## Release TODO

- Provision production SMTP/provider credentials, then run `scripts/release_go_no_go.sh --email-live-proof`.
- Run `scripts/stripe_billing_provision.py --confirm-live` with live Stripe keys, then run live billing proof.
- Add Apple signing secrets to GitHub or run `securewave_app/scripts/archive_ios_release.sh` on a Mac with Apple signing assets to produce the final signed iOS archive/export.
- Produce and publish the Intel macOS UI demo zip if Intel Mac download support is required; the Apple Silicon macOS UI demo zip is already published.
- Create the App Store reviewer account after SMTP is live; do not submit placeholder review credentials.
- If App Store Connect asks for entitlement justification again, request NetworkExtension Packet Tunnel Provider only, not Hotspot Helper.
