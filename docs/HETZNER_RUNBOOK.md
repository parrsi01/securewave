# Hetzner Runbook (SecureWave)

Hetzner Cloud is the only supported infrastructure provider for SecureWave. Other cloud providers are unsupported.

## Policy / Guardrails

- Provider: Hetzner Cloud only
- Server type: `cx23` / `cx33` only (default: `cx33`)
- Default fleet size: single server
  - Scaling beyond 1 server requires an explicit override (`allow_scale=true`)
- OS image: Ubuntu LTS (`ubuntu-22.04` or `ubuntu-24.04`)
- Token: use `HETZNER_API_TOKEN` (exported to Terraform as `TF_VAR_hcloud_token`)

## Provision (Terraform)

Terraform module: `infrastructure/hetzner/`

1. Export token:

```bash
export HETZNER_API_TOKEN="..."
export TF_VAR_hcloud_token="$HETZNER_API_TOKEN"
```

2. Create `infrastructure/hetzner/terraform.tfvars` (do not commit):

```hcl
ssh_key_names = ["your-ssh-key-name-in-hetzner"]
location = "ash"
server_type = "cx33"
node_count = 1
allow_scale = false
allow_http_https = true
```

3. Apply:

```bash
cd infrastructure/hetzner
terraform init
terraform apply
terraform output server_ipv4
```

Cost guardrail check (local + CI):

```bash
bash scripts/check_cost_guardrails.sh infrastructure/hetzner/terraform.tfvars
```

## Bootstrap Host Hardening (Ubuntu)

Bootstrap script (run once, as root):

```bash
ssh root@<server-ip> 'bash -s' < scripts/hetzner_bootstrap.sh
```

What it does (high level):
- Creates `securewave` admin user (sudo + docker)
- Enables IP forwarding
- Enables UFW with the production baseline:
  - `22/tcp`
  - `80/tcp`
  - `443/tcp`
  - `51820/udp`
  - `1194/udp`
  - `500/udp`
  - `4500/udp`
- Enables fail2ban with an explicit SSH jail
- Enables unattended security upgrades
- Installs `nginx`, `certbot`, and `python3-certbot-nginx`

## Install WireGuard (VPN Server)

WireGuard setup script (run once, as root):

```bash
ssh root@<server-ip> 'bash -s' < infrastructure/wireguard_vm_setup.sh
```

Fetch the server public key (required for clients):

```bash
ssh securewave@<server-ip> 'sudo cat /etc/wireguard/keys/server_public.key'
```

## Register Servers In SecureWave (Control Plane)

SecureWave issues real WireGuard profiles based on the VPN server registry in the database (`vpn_servers`).

Recommended (sync from Terraform outputs + Hetzner API + fetch WG public key over SSH):

```bash
export HETZNER_API_TOKEN="..."
export WG_SSH_USER="securewave"
export WG_SSH_KEY_PATH="$HOME/.ssh/<key>"

python3 infrastructure/hetzner/sync_vpn_servers.py --fetch-wg-public-key
```

Manual (single server):

```bash
python3 infrastructure/register_server.py \
  --server-id "securewave-01" \
  --location "Ashburn, US" \
  --country "US" \
  --country-code "US" \
  --city "Ashburn" \
  --public-ip "<server-ip>" \
  --hcloud-location "ash" \
  --wg-public-key "<wg-server-public-key-base64>"
```

## Backend Production Config (Must Be Explicit)

In production, SecureWave fails fast unless production config is explicit:

- `ENVIRONMENT=production`
- `TESTING` must not be enabled

You must also set:
- `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`
- `AUTH_ENCRYPTION_KEY`, `WG_ENCRYPTION_KEY`
- `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_BASIC_MONTHLY`, `STRIPE_PRICE_PREMIUM_MONTHLY`, `STRIPE_PRICE_ULTRA_MONTHLY`
- `EMAIL_PROVIDER=smtp` plus `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`/`FROM_EMAIL`
- `DATABASE_URL=postgresql+psycopg2://...`

Peer auto-registration (optional):
- Set `WG_AUTO_REGISTER_PEERS=true`
- Configure either SSH access (`WG_SSH_USER`, `WG_SSH_KEY_PATH`) or management API (`WG_API_KEY`, `WG_API_PORT`)

## Region Selection (Barbados + Europe)

- Caribbean/Barbados users: prefer Hetzner `ash` (Ashburn) as the nearest Hetzner location.
- Europe users: prefer `nbg1`, `fsn1`, or `hel1`.

SecureWave does not hardcode user geo assumptions; server selection is driven by the registered server fleet.

## Verification (No Live Traffic Required)

Local end-to-end simulation (excludes cloud traffic):

```bash
bash dev_tools/sandbox/realism/run_full_simulation.sh
```

This includes:
- signup/login
- device registration
- VPN profile fetch (WireGuard config structure)
- website flows
- pytest + flutter analyze/test

## Stop Condition

This repo is prepared to generate real WireGuard profiles backed by Hetzner server registry, but does not enable live traffic by default. Go live only after:
- a real server is provisioned + hardened
- the server public key + endpoint are registered in DB
- `TESTING` is not enabled in production
- peer auto-registration is configured intentionally (or explicitly disabled)
