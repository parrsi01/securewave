# Hetzner Provisioning

## Terraform module
Primary module: `infra/hetzner`

Guardrail check:
```bash
bash infra/hetzner/check_guardrails.sh
```

## Plan / apply / destroy
```bash
export HETZNER_API_TOKEN="<token>"
bash scripts/release_hetzner.sh plan
bash scripts/release_hetzner.sh apply
ALLOW_DESTROY=true CONFIRM_DESTROY=YES bash scripts/release_hetzner.sh destroy
```

Destroy is blocked unless both confirmations are provided.

## Register nodes in backend
`scripts/release_hetzner.sh apply` automatically runs:
```bash
python infrastructure/hetzner/sync_vpn_servers.py --terraform-dir infra/hetzner
```

to populate `vpn_servers`.
