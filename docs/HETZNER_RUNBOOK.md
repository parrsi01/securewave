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

## Audit the Active Fleet

The fleet audit accepts either `HETZNER_API_TOKEN` or the active authenticated
`hcloud` CLI context. The CLI-context path avoids copying or printing the API
token:

```bash
hcloud context active
python3 infrastructure/hetzner/audit_vpn_fleet.py \
  --only-running \
  --name-prefix securewave \
  --json-out /tmp/securewave-fleet-audit.json
```

## Register Servers In SecureWave (Control Plane)

SecureWave issues real WireGuard profiles based on the VPN server registry in the database (`vpn_servers`).

Production hides synthetic bootstrap aliases that point multiple city/country
rows at the same public IP. To show 4-5 public regions, provision and register
4-5 real data-plane nodes, or explicitly enable
`SECUREWAVE_ALLOW_SYNTHETIC_SERVER_BOOTSTRAP=true` only for a labeled demo.

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
- `SECUREWAVE_EGRESS_EVIDENCE_SECRET` (a unique 32+ character secret when OpenVPN or IKEv2 is provisioned)
- `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_BASIC_MONTHLY`, `STRIPE_PRICE_PREMIUM_MONTHLY`, `STRIPE_PRICE_ULTRA_MONTHLY`
- `EMAIL_PROVIDER=smtp` plus `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`/`FROM_EMAIL`
- `DATABASE_URL=postgresql+psycopg2://...`

Peer auto-registration (optional):
- Set `WG_AUTO_REGISTER_PEERS=true`
- Configure either SSH access (`WG_SSH_USER`, `WG_SSH_KEY_PATH`) or management API (`WG_API_KEY`, `WG_API_PORT`)

## OpenVPN (Explicit Host Provisioning)

OpenVPN is never enabled merely by this provisioning or registry metadata. On an explicitly authorized Hetzner host, run the checked-in host script as root, retrieve only its public CA, and then sync the public metadata:

```bash
sudo infrastructure/hetzner/provision_openvpn_server.sh --public-host vpn.example.com --transport udp
sudo infrastructure/hetzner/provision_openvpn_server.sh --print-ca > /secure/path/openvpn-ca.pem
python3 infrastructure/hetzner/sync_vpn_servers.py \
  --fetch-wg-public-key --supports-openvpn \
  --openvpn-transport udp --openvpn-ca-cert-path /secure/path/openvpn-ca.pem
```

Do not commit the CA export path, server keys, SSH keys, egress-evidence secret, or generated profiles. The API/UI stay unavailable until the authenticated OpenVPN health probe and fresh independent data-plane evidence are both recorded. The Linux app then requires an authenticated HTTPS egress movement proof before marking OpenVPN connected. See [OPENVPN_HETZNER_RUNBOOK.md](OPENVPN_HETZNER_RUNBOOK.md) for the scoped credential and proxy requirements.

## IKEv2 (Dedicated Gateway Provisioning)

IKEv2 uses a dedicated `charon-systemd`/`swanctl` gateway, not the Linux
client's `charon-nm` process. The host provisioning script refuses a shared
strongSwan installation and creates only root-owned SecureWave credential and
networking state. After explicitly authorizing a gateway, provision it, export
only its public CA, and register the certificate identity:

```bash
sudo infrastructure/hetzner/provision_ikev2_server.sh --public-host vpn.example.com
sudo infrastructure/hetzner/provision_ikev2_server.sh --print-ca > /secure/path/securewave-ikev2-ca.pem
python3 infrastructure/hetzner/sync_vpn_servers.py \
  --fetch-wg-public-key --supports-ikev2 \
  --ikev2-remote-id vpn.example.com \
  --ikev2-ca-cert-path /secure/path/securewave-ikev2-ca.pem
```

The inventory flag does not enable IKEv2. Authenticated gateway health, fresh
matching data-plane evidence, a clean contract-13 client runtime, HTTPS egress
movement, ESP/XFRM evidence, and residue cleanup are all required first. See
[IKEV2_HETZNER_RUNBOOK.md](IKEV2_HETZNER_RUNBOOK.md) for lifecycle, routing-loop,
lab, and redaction requirements.

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
